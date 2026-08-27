//! Headless TrUAPI hosts for local end-to-end testing.
//!
//! Two roles, one binary, pairing over the real People-chain statement store:
//! - `pairing-host`: a seedless host that presents a pairing deeplink and
//!   serves product frames over WebSocket (the surface a product/test driver
//!   talks to).
//! - `signing-host`: a wallet-local host that answers a pairing deeplink and
//!   auto-signs, replacing the external signing-bot in e2e.
//!
//! Plus the diagnostics and one-shot commands: `identity-check` for the dotNS
//! usernames of a mnemonic's accounts, `register-name` for a full-person
//! username, `alloc-check` for statement-store allowance, and `pgas-check` for
//! an Asset Hub PGAS allowance claim.

mod accounts;
mod attestation;
mod chain;
mod chat;
mod dotns_read;
mod frame_server;
mod network;
mod platform;
mod register_name;
mod script_runner;
mod sessions;
mod signing_shell;
mod terminal_ui;
mod update;

use std::collections::HashMap;
use std::fmt;
use std::future::Future;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::process::ExitStatus;
use std::str::FromStr;
use std::sync::Arc;

use anyhow::{Context, Result, bail};
use clap::{Args, Parser, Subcommand, ValueEnum};
use futures::future::BoxFuture;
use tracing_subscriber::Layer;
use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::util::SubscriberInitExt;
use truapi_platform::{
    ChatPlatform, HostInfo, PermissionStatusHost, PlatformInfo, ProductExecutionKind,
};
use truapi_server::host_logic::dotns_gateway::{
    MAX_BASE_LABEL_LEN, MIN_PERSON_LABEL_LEN, is_registrable_full_label,
};
use truapi_server::statement_allowance as alloc;
use truapi_server::subscription::Spawner;
use truapi_server::{
    PairedSsoPeer, PairingHostConfig, PairingHostRuntime, ResponderExit, SigningHostConfig,
    SigningHostRuntime, StatementRenewalTarget,
};

use crate::accounts::{ResolveSignerConfig, ResolvedSigner};
use crate::network::{Network, NetworkConfig};
use crate::platform::{ApprovalPolicy, CliPlatform, CliStoragePaths};
use crate::sessions::{
    DEFAULT_SESSION_NAME, PairedHost, PairedHostMetadata, SessionCatalog, SessionClearTarget,
    SessionProfile,
};
use crate::signing_shell::{
    DeviceCommand, HELP_TEXT, PAIRING_HELP_TEXT, ProductCommand, SessionCommand, ShellCommand,
    parse_command,
};
use crate::terminal_ui::{
    ActiveTerminalUi, ActivityState, DriveResult, SystemEvent, TerminalUi, UiHandle,
};

/// Default product served by the pairing host's frame endpoint. Product ids
/// must be a dotNS name (`.dot`, `.paseo` or `.test`) or a `localhost`
/// identifier (host-spec product id).
const DEFAULT_PRODUCT_ID: &str = "headless-playground.dot";
/// Deeplink scheme advertised by the pairing host.
const DEEPLINK_SCHEME: &str = "polkadotapp";

#[derive(Parser)]
#[command(
    name = "truapi-host",
    about = "Headless TrUAPI hosts for e2e testing",
    version = update::CURRENT_VERSION
)]
struct Cli {
    /// Log verbosity. `RUST_LOG` takes precedence when set.
    #[arg(
        long,
        global = true,
        value_enum,
        env = "TRUAPI_HOST_LOG",
        default_value = "info"
    )]
    log_level: LogLevel,
    #[command(subcommand)]
    command: Command,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
enum LogLevel {
    Error,
    Warn,
    Info,
    Debug,
    Trace,
}

impl LogLevel {
    const fn as_filter(self) -> &'static str {
        match self {
            Self::Error => "error",
            Self::Warn => "warn",
            Self::Info => "info",
            Self::Debug => "debug",
            Self::Trace => "trace",
        }
    }

    fn scoped_filter(self) -> String {
        let level = self.as_filter();
        format!(
            "warn,truapi={level},truapi_host={level},truapi_platform={level},truapi_server={level}"
        )
    }
}

impl FromStr for LogLevel {
    type Err = String;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match value.trim().to_ascii_lowercase().as_str() {
            "error" => Ok(Self::Error),
            "warn" => Ok(Self::Warn),
            "info" => Ok(Self::Info),
            "debug" => Ok(Self::Debug),
            "trace" => Ok(Self::Trace),
            _ => Err(format!(
                "invalid log level `{value}`; expected error, warn, info, debug, or trace"
            )),
        }
    }
}

impl fmt::Display for LogLevel {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_filter())
    }
}

#[derive(Clone)]
struct LogController {
    reload: Arc<dyn Fn(LogLevel) -> Result<(), String> + Send + Sync>,
}

impl LogController {
    fn set(&self, level: LogLevel) -> Result<()> {
        (self.reload)(level).map_err(anyhow::Error::msg)
    }
}

#[derive(Subcommand)]
enum Command {
    /// Run a seedless pairing host for product scripts or interactive pairing.
    ///
    /// With `--script`, exits with the script's status. Without it, stays in an
    /// interactive terminal UI where scripts can be run repeatedly.
    PairingHost(PairingHostArgs),
    /// Run a wallet-local signing host for scripts or pairing deeplinks.
    ///
    /// Owns signer identity, auto-manages accounts when no mnemonic/account is
    /// specified, and can accept pairing deeplinks. With `--script`, exits with
    /// the script's status; otherwise stays interactive.
    SigningHost(SigningHostArgs),
    /// Probe the dotNS contracts on Asset Hub for a mnemonic's registered
    /// identity/username.
    IdentityCheck {
        /// BIP-39 mnemonic to probe.
        #[arg(long, env = "HOST_CLI_SIGNER_MNEMONIC")]
        mnemonic: String,
        /// Network preset to probe.
        #[arg(long, value_enum, default_value = "paseo-next-v2")]
        network: Network,
    },
    /// Register a full-person username on dotNS via
    /// `DotnsGateway.register_name` on Asset Hub. Requires a recognized full
    /// person. That person's People ring must have propagated to Asset Hub.
    RegisterName {
        /// BIP-39 mnemonic of the recognized full person.
        #[arg(long, env = "HOST_CLI_SIGNER_MNEMONIC")]
        mnemonic: String,
        /// Network preset to use.
        #[arg(long, value_enum, default_value = "paseo-next-v2")]
        network: Network,
        /// Base label to register (lowercase ASCII letters only).
        #[arg(long)]
        label: String,
        /// Dotted lite username to link (`name.NN`). Defaults to the
        /// account's own lite username.
        #[arg(long, conflicts_with = "chat_key")]
        link_lite: Option<String>,
        /// 65-byte ECDH chat key (hex). Use it for a standalone registration
        /// with no lite-username link.
        #[arg(long)]
        chat_key: Option<String>,
    },
    /// Check (and optionally submit) a statement-store allowance registration
    /// against the real People chain: ring membership, the chosen slot, and
    /// (with `--submit`) the `set_statement_store_account` extrinsic.
    AllocCheck {
        /// BIP-39 mnemonic proving LitePeople ring membership.
        #[arg(long, env = "HOST_CLI_SIGNER_MNEMONIC")]
        mnemonic: String,
        /// Network preset to use for People-chain RPC.
        #[arg(long, value_enum, default_value = "paseo-next-v2")]
        network: Network,
        /// Target account (hex, 32 bytes) to grant allowance to. Defaults to
        /// all-zero (read-only slot scan only).
        #[arg(long)]
        target: Option<String>,
        /// How many rings back from the current index to scan for our member.
        #[arg(long, default_value_t = 8)]
        lookback: u32,
        /// Submit the extrinsic instead of only checking membership + slot.
        #[arg(long)]
        submit: bool,
    },
    /// Diagnose (or `--submit`) an Asset Hub PGAS allowance claim: ring
    /// membership on People, revision propagation to Asset Hub, the day's free
    /// slot, and the `Pgas.claim_pgas` extrinsic.
    PgasCheck {
        /// BIP-39 mnemonic proving LitePeople ring membership.
        #[arg(long, env = "HOST_CLI_SIGNER_MNEMONIC")]
        mnemonic: String,
        /// Network preset to use for People and Asset Hub RPC.
        #[arg(long, value_enum, default_value = "paseo-next-v2")]
        network: Network,
        /// Account (hex, 32 bytes) the claim credits. Required with `--submit`.
        #[arg(long)]
        target: Option<String>,
        /// How many rings back from the current index to scan for our member.
        #[arg(long, default_value_t = 8)]
        lookback: u32,
        /// Submit the claim instead of only reporting what it would do.
        #[arg(long)]
        submit: bool,
    },
    /// Install the current stable release over this one.
    ///
    /// Only works for a binary the installer put in place; a `cargo install`
    /// copy or a source build is reported and left alone.
    Update,
}

/// Execution kind the CLI serves a product as.
#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
enum ExecutionKind {
    /// Ordinary full-page product. Chat requests answer `Denied`, as they do
    /// on any host that does not serve chat.
    App,
    /// Headless executable served by the CLI's in-memory chat host.
    Worker,
}

impl ExecutionKind {
    fn context(self) -> ProductExecutionKind {
        match self {
            Self::App => ProductExecutionKind::App,
            Self::Worker => ProductExecutionKind::Worker,
        }
    }

    /// The chat host to install, if this kind serves chat at all.
    fn chat_host(self) -> Option<Arc<chat::CliChatHost>> {
        matches!(self, Self::Worker).then(chat::CliChatHost::from_env)
    }
}

#[derive(Args)]
struct PairingHostArgs {
    /// Execution kind the served product runs as. `worker` installs the CLI's
    /// in-memory chat host; `app` leaves Chat unserved.
    #[arg(long = "execution-kind", value_enum, default_value = "app")]
    execution_kind: ExecutionKind,
    /// Product script to run (JS/TS). If omitted, start the terminal UI.
    #[arg(long)]
    script: Option<PathBuf>,
    /// Product id the host serves; scopes storage and product accounts.
    #[arg(long = "product-id", default_value = DEFAULT_PRODUCT_ID)]
    product_id: String,
    /// TCP address to serve product WebSocket frames on. When omitted, use a
    /// private per-process Unix-domain socket.
    #[arg(long)]
    frame_listen: Option<SocketAddr>,
    /// Root directory for CLI-managed host state.
    #[arg(long = "base-path", env = "TRUAPI_HOST_BASE_PATH")]
    base_path: Option<PathBuf>,
    /// Network preset that supplies all RPC/backend/genesis config.
    #[arg(long, value_enum, default_value = "paseo-next-v2")]
    network: Network,
    /// Approve every confirmation without prompting on the CLI.
    #[arg(long)]
    auto_accept: bool,
}

#[derive(Args)]
struct SigningHostArgs {
    /// Execution kind the served product runs as. `worker` installs the CLI's
    /// in-memory chat host; `app` leaves Chat unserved.
    #[arg(long = "execution-kind", value_enum, default_value = "app")]
    execution_kind: ExecutionKind,
    /// Product script to run (JS/TS). If omitted, start an interactive shell.
    #[arg(long)]
    script: Option<PathBuf>,
    /// Product id used by scripts and product-scoped operations.
    #[arg(long = "product-id", default_value = DEFAULT_PRODUCT_ID)]
    product_id: String,
    /// Pairing deeplink to add. Managed interactive and serve sessions also
    /// restore responders for every previously paired host.
    #[arg(long)]
    deeplink: Option<String>,
    /// BIP-39 mnemonic for the wallet root. If omitted, the
    /// `HOST_CLI_SIGNER_MNEMONIC` env var is used when set. Any mnemonic
    /// bypasses account auto-management.
    #[arg(long, env = "HOST_CLI_SIGNER_MNEMONIC")]
    mnemonic: Option<String>,
    /// Named stored account to use. Omit this and `--mnemonic` to auto-select
    /// or create a usable account.
    #[arg(long)]
    account: Option<String>,
    /// Persistent signing-host session to restore or create.
    #[arg(long)]
    session: Option<String>,
    /// Prefix for newly-created lite usernames in auto-account mode.
    #[arg(long = "lite-username-prefix")]
    lite_username_prefix: Option<String>,
    /// Full-person base name a newly-created auto account reserves on dotNS
    /// alongside its lite username, to claim later as a full person.
    #[arg(long = "reserved-username")]
    reserved_username: Option<String>,
    /// Root directory for CLI-managed account and host state.
    #[arg(long = "base-path", env = "TRUAPI_HOST_BASE_PATH")]
    base_path: Option<PathBuf>,
    /// Network preset that supplies all RPC/backend/genesis config.
    #[arg(long, value_enum, default_value = "paseo-next-v2")]
    network: Network,
    /// TCP address to serve product WebSocket frames on. When omitted, use a
    /// private per-process Unix-domain socket.
    #[arg(long)]
    frame_listen: Option<SocketAddr>,
    /// Approve every confirmation without prompting on the CLI.
    #[arg(long)]
    auto_accept: bool,
    /// Serve product frames without a terminal UI and stay up until stopped.
    /// Needs no TTY, so a dev server can supervise this process: the frame
    /// endpoint and every lifecycle event are logged one line at a time, and
    /// the signer is ready once "Signing host ready" is printed. Pair it with
    /// `--auto-accept`, because a process with no terminal cannot prompt.
    #[arg(long)]
    serve: bool,
    /// Execute one slash command without starting the terminal UI.
    #[command(subcommand)]
    action: Option<SigningHostAction>,
}

#[derive(Subcommand)]
enum SigningHostAction {
    /// Execute one slash command and exit.
    Exec {
        /// Slash command to execute, such as `/session`.
        command: String,
    },
}

#[tokio::main]
async fn main() -> Result<()> {
    // Install a rustls crypto provider so `wss://` chain connections work;
    // rustls 0.23 panics without a process-level default provider.
    let _ = rustls::crypto::ring::default_provider().install_default();

    let cli = Cli::parse();
    let filter = tracing_subscriber::EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new(cli.log_level.scoped_filter()));
    let (filter, reload) = tracing_subscriber::reload::Layer::new(filter);
    let log_controller = LogController {
        reload: Arc::new(move |level| {
            reload
                .reload(tracing_subscriber::EnvFilter::new(level.scoped_filter()))
                .map_err(|error| error.to_string())
        }),
    };
    let log_layer = tracing_subscriber::fmt::layer()
        .with_ansi(false)
        .without_time()
        .with_target(false)
        .with_level(false)
        .with_writer(terminal_ui::LogWriter::default)
        .with_filter(filter)
        .with_filter(tracing_subscriber::filter::filter_fn(|metadata| {
            log_target_is_visible(metadata.target())
        }));
    tracing_subscriber::registry()
        .with(terminal_ui::SsoTranscriptLayer)
        .with(log_layer)
        .init();

    // A background check runs alongside the command rather than delaying it, and
    // reports through `tracing`, which the terminal UI renders in its transcript
    // so it cannot corrupt the full-screen display. The command then waits for
    // it at exit, so even a short one completes the download it started.
    let check = (!matches!(cli.command, Command::Update)).then(|| {
        update::report_pending_version();
        tokio::spawn(update::run_background_check())
    });

    let outcome = dispatch(cli.command, cli.log_level, log_controller).await;

    if let Some(check) = check {
        update::finish_background_check(check).await;
    }
    outcome
}

/// Run the requested command.
///
/// Separate from `main` so that the `?` several arms use returns here, leaving
/// `main` free to always wait for the update check it started.
async fn dispatch(
    command: Command,
    log_level: LogLevel,
    log_controller: LogController,
) -> Result<()> {
    match command {
        Command::Update => update::run_update_command().await,
        Command::PairingHost(args) => run_pairing_host(args, log_level, log_controller).await,
        Command::SigningHost(args) => run_signing_host(args, log_level, log_controller).await,
        Command::IdentityCheck { mnemonic, network } => {
            let entropy = bip39::Mnemonic::parse(mnemonic.trim())
                .context("invalid BIP-39 mnemonic")?
                .to_entropy();
            attestation::check_identity(network.config().asset_hub_ws, &entropy).await
        }
        Command::RegisterName {
            mnemonic,
            network,
            label,
            link_lite,
            chat_key,
        } => {
            let entropy = bip39::Mnemonic::parse(mnemonic.trim())
                .context("invalid BIP-39 mnemonic")?
                .to_entropy();
            let chat_key = chat_key
                .map(|value| -> Result<[u8; 65]> {
                    let bytes = hex::decode(value.strip_prefix("0x").unwrap_or(&value))
                        .context("chat key is not valid hex")?;
                    bytes.try_into().map_err(|bytes: Vec<u8>| {
                        anyhow::anyhow!("chat key must be 65 bytes, got {}", bytes.len())
                    })
                })
                .transpose()?;
            register_name::register_name(&register_name::RegisterNameConfig {
                network: network.config(),
                entropy,
                label,
                link_lite,
                chat_key,
            })
            .await
        }
        Command::AllocCheck {
            mnemonic,
            network,
            target,
            lookback,
            submit,
        } => run_alloc_check(mnemonic, network.config(), target, lookback, submit).await,
        Command::PgasCheck {
            mnemonic,
            network,
            target,
            lookback,
            submit,
        } => run_pgas_check(mnemonic, network.config(), target, lookback, submit).await,
    }
}

/// Diagnose an Asset Hub PGAS claim, and optionally submit it.
///
/// Connects to both chains directly rather than through the host's
/// `ChainProvider`, because a diagnostic should not depend on a host being wired
/// up. The provider would route Asset Hub correctly now that the preset serves it
/// as a role, so this is a choice about the subcommand rather than a workaround.
async fn run_pgas_check(
    mnemonic: String,
    network: crate::network::NetworkConfig,
    target: Option<String>,
    lookback: u32,
    submit: bool,
) -> Result<()> {
    use std::sync::Arc;

    use truapi_server::statement_allowance::pgas;

    let entropy = bip39::Mnemonic::parse(mnemonic.trim())
        .context("invalid BIP-39 mnemonic")?
        .to_entropy();
    let candidates = accounts::collection_candidates(&entropy);

    if submit && target.is_none() {
        bail!("--target is required with --submit; a claim has to credit an account");
    }
    let target = match target {
        Some(hex_str) => {
            let bytes = hex::decode(hex_str.strip_prefix("0x").unwrap_or(&hex_str))
                .context("invalid --target hex")?;
            <[u8; 32]>::try_from(bytes.as_slice())
                .map_err(|_| anyhow::anyhow!("--target must be 32 bytes"))?
        }
        None => [0u8; 32],
    };

    let people_rpc = alloc::rpc::RpcClient::connect(network.people_ws)
        .await
        .map_err(anyhow::Error::msg)?;
    let people_metadata = alloc::fetch_metadata(&people_rpc)
        .await
        .map_err(anyhow::Error::msg)?;
    let asset_hub_rpc = alloc::rpc::RpcClient::connect(network.asset_hub_ws)
        .await
        .map_err(anyhow::Error::msg)?;
    let asset_hub_metadata = alloc::fetch_metadata(&asset_hub_rpc)
        .await
        .map_err(anyhow::Error::msg)?;
    let asset_hub_state = alloc::fetch_chain_state(&asset_hub_rpc)
        .await
        .map_err(anyhow::Error::msg)?;
    println!(
        "asset hub: metadata V{} specVersion={} txVersion={} genesis=0x{}",
        asset_hub_metadata.metadata_version(),
        asset_hub_state.spec_version,
        asset_hub_state.transaction_version,
        hex::encode(asset_hub_state.genesis_hash),
    );

    for candidate in &candidates {
        println!(
            "{} member=0x{}",
            candidate.collection,
            hex::encode(alloc::proof::member_key(candidate.entropy))
        );
    }
    let memberships =
        alloc::find_including_rings(&people_rpc, &people_metadata, &candidates, lookback)
            .await
            .map_err(anyhow::Error::msg)?;
    for membership in &memberships {
        println!(
            "member INCLUDED in {} ring_index={} exponent={} members={}",
            membership.collection(),
            membership.ring.ring_index,
            membership.ring.exponent,
            membership.ring.members.len()
        );
    }
    // The widest membership the signer actually holds; a claim needs exactly one.
    let Some(membership) = memberships.first() else {
        bail!("member is not in the last {lookback} rings of any collection (onboarding pending)");
    };
    let ring = &membership.ring;

    let revision = alloc::ring::read_ring_revision(
        &people_rpc,
        &people_metadata,
        ring.collection,
        ring.ring_index,
        &ring.block_hash,
    )
    .await
    .map_err(anyhow::Error::msg)?;
    println!("people ring revision={revision}");
    match pgas::await_ring_revision(
        &asset_hub_rpc,
        &asset_hub_metadata,
        ring.collection,
        ring.ring_index,
        revision,
    )
    .await
    {
        Ok(()) => println!("asset hub has imported revision {revision}"),
        Err(err) => bail!("asset hub cannot authorize this ring: {err}"),
    }

    let day = alloc::slot::current_period(
        alloc::slot::read_chain_now_seconds(&asset_hub_rpc)
            .await
            .map_err(anyhow::Error::msg)?,
    );
    let max = alloc::slot::max_pgas_claims(&asset_hub_metadata, ring.collection)
        .map_err(anyhow::Error::msg)?;
    println!(
        "day={day} max_claims_per_day={max} target=0x{}",
        hex::encode(target)
    );
    match alloc::slot::scan_pgas_slot_excluding(
        &asset_hub_rpc,
        &asset_hub_metadata,
        ring.collection,
        membership.entropy,
        day,
        &[],
    )
    .await
    {
        Ok(slot_index) => println!("slot scan: free slot_index={slot_index}"),
        Err(err) => println!("slot scan: {err}"),
    }

    if !submit {
        return Ok(());
    }

    let asset_hub = alloc::ChainContext {
        metadata: Arc::new(asset_hub_metadata),
        state: asset_hub_state,
    };
    let outcome = pgas::claim_pgas(pgas::PgasClaim {
        asset_hub_rpc: &asset_hub_rpc,
        asset_hub: &asset_hub,
        people_rpc: &people_rpc,
        people_metadata: &people_metadata,
        entropy: membership.entropy,
        target: &target,
        ring: &membership.ring,
    })
    .await
    .map_err(|err| anyhow::anyhow!("claim failed: {err}"))?;
    println!(
        "CLAIMED day={} slot_index={} ring_index={} block={}",
        outcome.day, outcome.slot_index, outcome.ring_index, outcome.block_hash
    );
    Ok(())
}

fn log_target_is_visible(target: &str) -> bool {
    target != terminal_ui::SSO_TRANSCRIPT_TARGET
        && target != "rustls"
        && !target.starts_with("rustls::")
        && target != "tungstenite::protocol"
        && !target.starts_with("tungstenite::protocol::")
}

/// Check statement-store allowance for a mnemonic: ring membership, the chosen
/// slot, and (with `submit`) the `set_statement_store_account` extrinsic.
async fn run_alloc_check(
    mnemonic: String,
    network: NetworkConfig,
    target: Option<String>,
    lookback: u32,
    submit: bool,
) -> Result<()> {
    let entropy = bip39::Mnemonic::parse(mnemonic.trim())
        .context("invalid BIP-39 mnemonic")?
        .to_entropy();
    let candidates = accounts::collection_candidates(&entropy);

    if submit && target.is_none() {
        bail!("--target is required with --submit; the all-zero default is read-only");
    }

    let target = match target {
        Some(hex_str) => {
            let bytes = hex::decode(hex_str.strip_prefix("0x").unwrap_or(&hex_str))
                .context("invalid --target hex")?;
            <[u8; 32]>::try_from(bytes.as_slice())
                .map_err(|_| anyhow::anyhow!("--target must be 32 bytes"))?
        }
        None => [0u8; 32],
    };

    let rpc = alloc::rpc::RpcClient::connect(network.people_ws)
        .await
        .map_err(anyhow::Error::msg)?;
    let metadata = alloc::fetch_metadata(&rpc)
        .await
        .map_err(anyhow::Error::msg)?;
    let chain_state = alloc::fetch_chain_state(&rpc)
        .await
        .map_err(anyhow::Error::msg)?;
    println!(
        "chain: specVersion={} txVersion={} genesis=0x{}",
        chain_state.spec_version,
        chain_state.transaction_version,
        hex::encode(chain_state.genesis_hash),
    );

    for candidate in &candidates {
        println!(
            "{} member=0x{} current_ring_index={}",
            candidate.collection,
            hex::encode(alloc::proof::member_key(candidate.entropy)),
            alloc::ring::read_current_ring_index(&rpc, candidate.collection)
                .await
                .map_err(anyhow::Error::msg)?,
        );
    }
    let memberships = alloc::find_including_rings(&rpc, &metadata, &candidates, lookback)
        .await
        .map_err(anyhow::Error::msg)?;
    if memberships.is_empty() {
        println!("member NOT in the last {lookback} rings of any collection (onboarding pending)");
    }
    for membership in &memberships {
        println!(
            "member INCLUDED in {} ring_index={} exponent={} included_members={}",
            membership.collection(),
            membership.ring.ring_index,
            membership.ring.exponent,
            membership.ring.members.len(),
        );
    }

    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .context("system clock before UNIX epoch")?
        .as_secs();
    let period = alloc::slot::current_period(now);
    println!("period={period} target=0x{}", hex::encode(target));

    for candidate in &candidates {
        if !candidate.collection.is_supported(&metadata) {
            println!("{}: not offered by this chain", candidate.collection);
            continue;
        }
        print!("{}: ", candidate.collection);
        report_slot_scan(&rpc, &metadata, *candidate, period, &target, now).await?;
    }

    if submit {
        if memberships.is_empty() {
            bail!("cannot submit: member not in any ring");
        }
        let scans = alloc::scan_collections(&rpc, &metadata, &candidates, period, &target, true)
            .await
            .map_err(anyhow::Error::msg)?;
        match alloc::register_statement_account_pooled(
            &rpc,
            &metadata,
            &chain_state,
            &scans,
            &memberships,
            alloc::PooledRegistrationParams {
                target: &target,
                period,
                reuse_existing: true,
                // A diagnostic that submits behaves as it did before pooling,
                // where a full table was replaced rather than reported.
                allow_eviction: true,
                protected: &[],
            },
        )
        .await
        {
            Ok(alloc::RegistrationOutcome::Registered {
                block_hash,
                seq,
                ring_index,
                collection,
            }) => println!(
                "REGISTERED in {collection} seq={seq} ring_index={ring_index} block={block_hash}"
            ),
            Ok(alloc::RegistrationOutcome::AlreadyAllocated { seq, collection }) => {
                println!("already allocated in {collection} at seq={seq}")
            }
            Err(err) => bail!("registration failed: {err}"),
        }
    }

    Ok(())
}

/// Print one collection's slot table for `period`: the free or reusable slot, or
/// the full table with each occupant's age against the chain clock.
async fn report_slot_scan(
    rpc: &alloc::rpc::RpcClient,
    metadata: &alloc::extension::Metadata,
    candidate: alloc::CollectionCandidate,
    period: u32,
    target: &[u8; 32],
    now: u64,
) -> Result<()> {
    match alloc::slot::scan_slot_excluding(
        rpc,
        metadata,
        alloc::slot::SlotScan {
            collection: candidate.collection,
            entropy: candidate.entropy,
            period,
            target,
            excluded: &[],
            reuse_existing: true,
        },
    )
    .await
    {
        Ok(alloc::slot::SlotSelection::Free(seq)) => println!("slot scan: free seq={seq}"),
        Ok(alloc::slot::SlotSelection::FreeSlotsExcluded) => {
            println!("slot scan: free slots exist but are awaiting earlier submissions");
        }
        Ok(alloc::slot::SlotSelection::Full { max, occupied }) => {
            println!("slot scan: all {max} slots taken, none reusable");
            let cooldown = alloc::slot::replacement_cooldown(metadata)?;
            // The runtime judges ages against its own clock, which trails ours.
            let chain_now = alloc::slot::read_chain_now_seconds(rpc).await?;
            println!(
                "  chain clock={chain_now} (host clock is {}s ahead)",
                now.saturating_sub(chain_now)
            );
            for slot in &occupied {
                let age = chain_now.saturating_sub(slot.since);
                let state = if age >= cooldown {
                    "replaceable"
                } else {
                    "in cooldown"
                };
                println!(
                    "  seq={} since={} age={age}s {state} account=0x{}",
                    slot.seq,
                    slot.since,
                    hex::encode(slot.account_id)
                );
            }
            match alloc::slot::replaceable_slot(&occupied, target, chain_now, cooldown, &[]) {
                Some(seq) => println!("would replace seq={seq} (oldest replaceable)"),
                None => println!("nothing replaceable: cooldown={cooldown}s"),
            }
        }
        Ok(alloc::slot::SlotSelection::AlreadyAllocated(seq)) => {
            println!("slot scan: target already allocated at seq={seq}")
        }
        Err(err) => println!("slot scan: {err}"),
    }

    Ok(())
}

/// Map the `--auto-accept` flag to an approval policy: auto-accept, or prompt
/// each confirmation on the CLI.
fn approval_policy(auto_accept: bool) -> ApprovalPolicy {
    if auto_accept {
        ApprovalPolicy::AutoAccept
    } else {
        ApprovalPolicy::Prompt
    }
}

/// Spawner that runs runtime futures on the tokio runtime, so their WebSocket
/// connects and timers have a reactor.
fn tokio_spawner() -> Spawner {
    Arc::new(|fut: BoxFuture<'static, ()>| {
        tokio::spawn(fut);
    })
}

fn host_info(name: &str) -> HostInfo {
    HostInfo {
        name: name.to_string(),
        icon: None,
        version: Some(env!("CARGO_PKG_VERSION").to_string()),
        platform: truapi::latest::HostPlatform::Cli,
    }
}

fn platform_info() -> PlatformInfo {
    PlatformInfo {
        kind: Some("cli".to_string()),
        version: Some(env!("CARGO_PKG_VERSION").to_string()),
    }
}

async fn run_pairing_host(
    args: PairingHostArgs,
    initial_log_level: LogLevel,
    log_controller: LogController,
) -> Result<()> {
    let interactive = args.script.is_none();
    if interactive && !terminal_ui::is_interactive_terminal() {
        invalid_invocation(
            "interactive pairing-host requires a TTY; use pairing-host --script <path>",
        );
    }
    let network = args.network.config();
    let base_path = args.base_path.unwrap_or_else(default_base_path);
    let product =
        frame_server::ProductSelection::new(args.product_id, args.execution_kind.context())?;
    let product_id = product.current();
    let storage_paths = CliStoragePaths::pairing(base_path.join(network.id));
    let (terminal_ui, ui_handle) = if interactive {
        let (ui, handle) =
            TerminalUi::new_pairing(network.id, product_id.clone(), initial_log_level);
        (Some(ui.enter()?), Some(handle))
    } else {
        (None, None)
    };
    let platform = CliPlatform::new(
        network,
        Some(storage_paths),
        approval_policy(args.auto_accept),
        ui_handle,
    );
    // SSO runs over the real People chain. Usernames resolve from the dotNS
    // contracts on Asset Hub.
    let config = PairingHostConfig::new(
        host_info("Headless Pairing Host"),
        platform_info(),
        network.people_genesis,
        network.bulletin_genesis,
        network.asset_hub_genesis,
        DEEPLINK_SCHEME.to_string(),
    )
    .context("invalid pairing host config")?;
    let storage_platform = platform.clone();
    let chat_host = args.execution_kind.chat_host();
    let status_host = platform.clone() as Arc<dyn PermissionStatusHost>;
    let pairing_runtime = Arc::new(PairingHostRuntime::with_chat_platform(
        platform,
        config,
        tokio_spawner(),
        chat_host.map(|chat| chat as Arc<dyn ChatPlatform>),
    ));
    pairing_runtime.set_permission_status_host(status_host);

    let frame_server = frame_server::bind(args.frame_listen).await?;
    let frame_url = frame_server.endpoint().to_string();
    terminal_ui::output_event(SystemEvent::FramesListening {
        url: frame_url.clone(),
    });
    let runtime_for_frames: Arc<dyn frame_server::ProductRuntimeFactory> = pairing_runtime.clone();

    if let Some(script) = args.script {
        let script_product_id = product_id.clone();
        let script_frame_url = frame_url.clone();
        let status = with_frame_server(runtime_for_frames, product, frame_server, async move {
            script_runner::run(
                &script_frame_url,
                &script_product_id,
                &script,
                script_runner::ScriptHostRole::PairingHost,
            )
            .await
        })
        .await?;
        let code = status.code().unwrap_or(1);
        terminal_ui::output_event(SystemEvent::ScriptExit { code });
        std::process::exit(code);
    }

    let terminal_ui = terminal_ui.context("interactive terminal was not initialized")?;
    with_frame_server(
        runtime_for_frames,
        product.clone(),
        frame_server,
        async move {
            pairing_interactive_loop(
                frame_url,
                product,
                pairing_runtime,
                storage_platform,
                terminal_ui,
                log_controller,
            )
            .await
        },
    )
    .await
}

async fn run_signing_host(
    args: SigningHostArgs,
    initial_log_level: LogLevel,
    log_controller: LogController,
) -> Result<()> {
    if let Err(error) = validate_signing_args(&args) {
        invalid_invocation(error);
    }
    let exec_input = args
        .action
        .as_ref()
        .map(|SigningHostAction::Exec { command }| command.clone());
    let interactive = args.script.is_none() && exec_input.is_none() && !args.serve;
    if interactive && !terminal_ui::is_interactive_terminal() {
        invalid_invocation(
            "interactive signing-host requires a TTY; use --serve to run headless, or `signing-host exec '/script path.ts'`, or --script",
        );
    }
    let exec_command = exec_input
        .as_deref()
        .map(|input| parse_command(input).unwrap_or_else(|error| invalid_invocation(error)));
    let product = frame_server::ProductSelection::new(
        args.product_id.clone(),
        args.execution_kind.context(),
    )?;
    let product_id = product.current();
    let network = args.network.config();
    let base_path = args.base_path.clone().unwrap_or_else(default_base_path);
    let session_catalog = SessionCatalog::new(base_path.clone(), network.id)?;
    let initial_session_name = initial_session_name(&args, &session_catalog);
    if normalized(args.mnemonic.clone()).is_none() {
        session_catalog.set_current(&initial_session_name)?;
    }
    let initial_session_names = session_catalog.list()?;
    let (terminal_ui, ui_handle) = if interactive {
        let (ui, handle) = TerminalUi::new(
            network.id,
            product_id,
            initial_session_name.clone(),
            initial_session_names,
            initial_log_level,
        );
        (Some(ui.enter()?), Some(handle))
    } else {
        (None, None)
    };
    let mut session = start_signing_host(
        &args,
        session_catalog,
        initial_session_name,
        network,
        ui_handle.clone(),
    )
    .await?;
    let frame_server = frame_server::bind(args.frame_listen).await?;
    let frame_url = frame_server.endpoint().to_string();
    terminal_ui::output_event(SystemEvent::FramesListening {
        url: frame_url.clone(),
    });
    let runtime_for_frames: Arc<dyn frame_server::ProductRuntimeFactory> =
        session.runtime_factory.clone();

    if let Some(script) = args.script {
        let product_id = product.current();
        let script_product_id = product_id.clone();
        let script_frame_url = frame_url.clone();
        let initial_deeplink = args.deeplink.clone();
        let status = with_frame_server(runtime_for_frames, product, frame_server, async move {
            if let Some(deeplink) = initial_deeplink {
                start_deeplink_responder(&mut session, deeplink).await?;
            }
            ensure_signer(&mut session).await?;
            let status = script_runner::run(
                &script_frame_url,
                &script_product_id,
                &script,
                script_runner::ScriptHostRole::SigningHost,
            )
            .await?;
            session.responders.stop_all();
            Ok::<ExitStatus, anyhow::Error>(status)
        })
        .await?;
        let code = status.code().unwrap_or(1);
        terminal_ui::output_event(SystemEvent::ScriptExit { code });
        std::process::exit(code);
    }

    if args.serve {
        let serve_deeplink = args.deeplink.clone();
        let serve_frame_url = frame_url.clone();
        let auto_accept = args.auto_accept;
        return with_frame_server(
            runtime_for_frames,
            product.clone(),
            frame_server,
            async move {
                ensure_signer(&mut session).await?;
                restore_paired_responders(&mut session).await;
                if let Some(deeplink) = serve_deeplink {
                    start_deeplink_responder(&mut session, deeplink).await?;
                }
                terminal_ui::output_event(SystemEvent::ServeReady {
                    url: serve_frame_url,
                    auto_accept,
                });
                wait_for_shutdown().await;
                session.responders.stop_all();
                Ok(())
            },
        )
        .await;
    }

    let initial_deeplink = args.deeplink.clone();
    if let Some(command) = exec_command {
        let cleanup_catalog = session.catalog.clone();
        let clear_target = with_frame_server(
            runtime_for_frames,
            product.clone(),
            frame_server,
            async move {
                if let Some(deeplink) = initial_deeplink {
                    start_deeplink_responder(&mut session, deeplink).await?;
                }
                let result = execute_non_interactive_command(
                    &mut session,
                    &frame_url,
                    &product,
                    command,
                    &log_controller,
                )
                .await;
                session.responders.stop_all();
                result
            },
        )
        .await?;
        if let Some(target) = clear_target {
            clear_sessions_after_shutdown(&cleanup_catalog, &target)?;
        }
        return Ok(());
    }

    let terminal_ui = terminal_ui.context("interactive terminal was not initialized")?;
    restore_paired_responders(&mut session).await;
    let cleanup_catalog = session.catalog.clone();
    let clear_target = with_frame_server(
        runtime_for_frames,
        product.clone(),
        frame_server,
        async move {
            signing_interactive_loop(
                &mut session,
                frame_url,
                product,
                initial_deeplink,
                terminal_ui,
                log_controller,
            )
            .await
        },
    )
    .await?;
    if let Some(target) = clear_target {
        clear_sessions_after_shutdown(&cleanup_catalog, &target)?;
    }
    Ok(())
}

struct SigningHostSession {
    runtime: Arc<SigningHostRuntime>,
    runtime_factory: Arc<frame_server::SwitchableSigningRuntime>,
    responders: ResponderManager,
    signer: Option<ResolvedSigner>,
    cached_user_id: Option<String>,
    last_script: Option<PathBuf>,
    catalog: SessionCatalog,
    profile: Option<SessionProfile>,
    network: NetworkConfig,
    mnemonic: Option<String>,
    default_account: Option<String>,
    lite_username_prefix: Option<String>,
    reserved_username: Option<String>,
    approval: ApprovalPolicy,
    ui: Option<UiHandle>,
    /// Set when this host serves a chat product. Held across runtime rebuilds
    /// so switching session keeps the rooms and messages already posted.
    chat: Option<Arc<chat::CliChatHost>>,
}

#[derive(Default)]
struct ResponderManager {
    tasks: HashMap<[u8; 32], tokio::task::JoinHandle<()>>,
}

impl ResponderManager {
    fn insert(&mut self, statement_account_id: [u8; 32], task: tokio::task::JoinHandle<()>) {
        if let Some(previous) = self.tasks.insert(statement_account_id, task) {
            previous.abort();
        }
    }

    fn remove(&mut self, statement_account_id: &[u8; 32]) -> bool {
        let Some(task) = self.tasks.remove(statement_account_id) else {
            return false;
        };
        task.abort();
        true
    }

    fn stop_all(&mut self) {
        for (_, task) in self.tasks.drain() {
            task.abort();
        }
    }
}

impl Drop for ResponderManager {
    fn drop(&mut self) {
        self.stop_all();
    }
}

fn initial_session_name(args: &SigningHostArgs, catalog: &SessionCatalog) -> String {
    if normalized(args.mnemonic.clone()).is_some() {
        return "ephemeral".to_string();
    }
    normalized(args.session.clone())
        .or_else(|| normalized(args.account.clone()).map(|_| DEFAULT_SESSION_NAME.to_string()))
        .unwrap_or_else(|| catalog.current_name())
}

async fn start_signing_host(
    args: &SigningHostArgs,
    catalog: SessionCatalog,
    session_name: String,
    network: NetworkConfig,
    ui: Option<UiHandle>,
) -> Result<SigningHostSession> {
    let mnemonic = normalized(args.mnemonic.clone());
    let mut profile = if mnemonic.is_some() {
        None
    } else {
        Some(catalog.ensure_profile(&session_name)?)
    };
    let default_account = normalized(args.account.clone());
    let mut cached_user_id = profile
        .as_ref()
        .map(|profile| catalog.cached_user_id(profile))
        .transpose()?
        .flatten();
    if let (Some(current), Some(user_id)) = (&profile, &cached_user_id)
        && current.name != *user_id
    {
        profile = Some(catalog.promote_to_user(current, user_id)?);
    }
    let cached_account_name = profile
        .as_ref()
        .map(|profile| catalog.cached_account_name(profile))
        .transpose()?
        .flatten();
    let selected_account = cached_account_name.or_else(|| {
        profile
            .as_ref()
            .is_some_and(|profile| profile.name == DEFAULT_SESSION_NAME)
            .then(|| default_account.clone())
            .flatten()
    });
    let mut signer = profile
        .as_ref()
        .map(|profile| {
            accounts::resolve_cached_signer(
                &profile.account_base_path,
                network.id,
                selected_account.as_deref(),
            )
        })
        .transpose()?
        .flatten();
    if let (Some(current), Some(user_id)) = (
        &profile,
        signer
            .as_ref()
            .and_then(|signer| signer.lite_username.as_ref()),
    ) && current.name != *user_id
    {
        profile = Some(catalog.promote_to_user(current, user_id)?);
        cached_user_id = Some(user_id.clone());
    }
    let storage_profile = profile.as_ref().cloned().unwrap_or_else(|| {
        catalog
            .profile(DEFAULT_SESSION_NAME)
            .expect("default session profile is valid")
    });
    if signer.is_none() && mnemonic.is_some() {
        let mut explicit_signer = accounts::resolve_signer(ResolveSignerConfig {
            base_path: &storage_profile.account_base_path,
            network,
            mnemonic: mnemonic.clone(),
            account: None,
            lite_username_prefix: None,
            reserved_username: None,
        })
        .await?;
        match attestation::registered_lite_username(network.asset_hub_ws, &explicit_signer.entropy)
            .await
        {
            Ok(user_id) => explicit_signer.lite_username = Some(user_id),
            Err(error) => {
                tracing::warn!(%error, "explicit signer has no resolvable dotNS username")
            }
        }
        signer = Some(explicit_signer);
    }
    let approval = approval_policy(args.auto_accept);
    let chat = args.execution_kind.chat_host();
    let runtime = build_signing_runtime(
        network,
        storage_profile.path,
        storage_profile.product_storage_dir,
        approval,
        ui.clone(),
        chat.clone(),
    )?;
    let runtime_factory = frame_server::SwitchableSigningRuntime::new(runtime.clone());
    let last_script = profile
        .as_ref()
        .map(|profile| catalog.last_script(profile))
        .transpose()?
        .flatten();
    if let Some(cached_signer) = &signer {
        runtime
            .activate_local_session_with_identity(
                cached_signer.entropy.clone(),
                cached_signer.lite_username.clone(),
            )
            .await
            .map_err(|error| {
                anyhow::anyhow!("failed to activate cached session: {}", error.reason)
            })?;
        if let (Some(profile), Some(user_id)) = (&profile, &cached_signer.lite_username) {
            if let Some(account_name) = &cached_signer.account_name {
                catalog.store_signer_binding(profile, user_id, account_name)?;
            } else {
                catalog.store_user_id(profile, user_id)?;
            }
            cached_user_id = Some(user_id.clone());
            if let Some(ui) = &ui {
                ui.connection(user_id.clone());
            }
        }
        terminal_ui::output_event(SystemEvent::SigningHostReady);
    }
    if let Some(profile) = &profile
        && profile.name != session_name
    {
        catalog.set_current(&profile.name)?;
        if let Some(ui) = &ui {
            ui.session(profile.name.clone(), catalog.list()?);
        }
    }
    if profile.is_some()
        && signer.is_none()
        && let Some(ui) = &ui
    {
        ui.event(SystemEvent::SigningHostNeedsSession);
    }

    Ok(SigningHostSession {
        runtime,
        runtime_factory,
        responders: ResponderManager::default(),
        signer,
        cached_user_id,
        last_script,
        catalog,
        profile,
        network,
        mnemonic,
        default_account,
        lite_username_prefix: normalized(args.lite_username_prefix.clone()),
        reserved_username: normalized(args.reserved_username.clone()),
        approval,
        ui,
        chat,
    })
}

fn build_signing_runtime(
    network: NetworkConfig,
    storage_path: PathBuf,
    product_storage_dir: PathBuf,
    approval: ApprovalPolicy,
    ui: Option<UiHandle>,
    chat: Option<Arc<chat::CliChatHost>>,
) -> Result<Arc<SigningHostRuntime>> {
    let platform = CliPlatform::new(
        network,
        Some(CliStoragePaths::new(storage_path, product_storage_dir)),
        approval,
        ui,
    );
    let config = SigningHostConfig::new(
        host_info("Headless Signing Host"),
        platform_info(),
        network.people_genesis,
        network.bulletin_genesis,
    )
    .context("invalid signing host config")?;
    let status_host = platform.clone() as Arc<dyn PermissionStatusHost>;
    let runtime = Arc::new(SigningHostRuntime::with_chat_platform(
        platform,
        config,
        tokio_spawner(),
        chat.map(|chat| chat as Arc<dyn ChatPlatform>),
    ));
    runtime.set_permission_status_host(status_host);
    runtime.start_statement_allowance_renewal();
    Ok(runtime)
}

impl Drop for SigningHostSession {
    fn drop(&mut self) {
        self.responders.stop_all();
    }
}

fn validate_signing_args(args: &SigningHostArgs) -> Result<()> {
    let mnemonic = normalized(args.mnemonic.clone());
    let account = normalized(args.account.clone());
    let session = normalized(args.session.clone());
    let prefix = normalized(args.lite_username_prefix.clone());
    if args.script.is_some() && args.action.is_some() {
        bail!("--script cannot be combined with the exec subcommand");
    }
    if args.serve && args.script.is_some() {
        bail!("--serve cannot be combined with --script");
    }
    if args.serve && args.action.is_some() {
        bail!("--serve cannot be combined with the exec subcommand");
    }
    if mnemonic.is_some() && account.is_some() {
        bail!("--account cannot be used when --mnemonic or HOST_CLI_SIGNER_MNEMONIC is set");
    }
    if mnemonic.is_some() && session.is_some() {
        bail!("--session cannot be used when --mnemonic or HOST_CLI_SIGNER_MNEMONIC is set");
    }
    if mnemonic.is_some()
        && args.action.as_ref().is_some_and(|action| {
            let SigningHostAction::Exec { command } = action;
            matches!(parse_command(command), Ok(ShellCommand::Devices(_)))
        })
    {
        bail!("paired-device management is unavailable when launched with --mnemonic");
    }
    if account.is_some() && session.is_some() {
        bail!("--session cannot be combined with --account");
    }
    if let Some(session) = session {
        sessions::validate_selectable_name(&session).map_err(anyhow::Error::msg)?;
    }
    if mnemonic.is_some() && prefix.is_some() {
        bail!(
            "--lite-username-prefix cannot be used when --mnemonic or HOST_CLI_SIGNER_MNEMONIC is set"
        );
    }
    if account.is_some() && prefix.is_some() {
        bail!("--lite-username-prefix only applies when --account is omitted");
    }
    let reserved = normalized(args.reserved_username.clone());
    if mnemonic.is_some() && reserved.is_some() {
        bail!(
            "--reserved-username cannot be used when --mnemonic or HOST_CLI_SIGNER_MNEMONIC is set"
        );
    }
    if account.is_some() && reserved.is_some() {
        bail!("--reserved-username only applies when --account is omitted");
    }
    if let Some(reserved) = &reserved
        && !is_registrable_full_label(reserved)
    {
        bail!(
            "--reserved-username {reserved:?} is not a reservable base label: lowercase ASCII \
             letters only, {MIN_PERSON_LABEL_LEN} to {MAX_BASE_LABEL_LEN} bytes"
        );
    }
    Ok(())
}

fn normalized(value: Option<String>) -> Option<String> {
    value.and_then(|value| {
        let trimmed = value.trim().to_string();
        (!trimmed.is_empty()).then_some(trimmed)
    })
}

fn invalid_invocation(error: impl fmt::Display) -> ! {
    eprintln!("error: {error}");
    std::process::exit(2);
}

async fn with_frame_server<T, Fut>(
    runtime: Arc<dyn frame_server::ProductRuntimeFactory>,
    product: Arc<frame_server::ProductSelection>,
    frame_server: frame_server::BoundFrameServer,
    body: Fut,
) -> Result<T>
where
    Fut: Future<Output = Result<T>>,
{
    let server = tokio::spawn(frame_server::accept_loop(runtime, product, frame_server));
    let result = body.await;
    server.abort();
    result
}

fn paired_host_from_deeplink(deeplink: &str) -> Result<PairedHost> {
    use truapi_server::host_logic::sso::pairing::{
        VersionedHandshakeProposal, decode_pairing_deeplink, v2::MetadataKey,
    };

    let VersionedHandshakeProposal::V2(proposal) =
        decode_pairing_deeplink(deeplink).map_err(anyhow::Error::msg)?;
    let mut metadata = PairedHostMetadata::default();
    for entry in proposal.metadata {
        let value = safe_display_metadata(entry.1);
        match entry.0 {
            MetadataKey::HostName => metadata.host_name = value,
            MetadataKey::HostVersion => metadata.host_version = value,
            MetadataKey::HostIcon => metadata.host_icon = value,
            MetadataKey::PlatformType => metadata.platform_type = value,
            MetadataKey::PlatformVersion => metadata.platform_version = value,
            MetadataKey::Custom(_) => {}
        }
    }
    Ok(PairedHost::new(
        proposal.device.statement_account_id,
        proposal.device.encryption_public_key,
        metadata,
    ))
}

fn safe_display_metadata(value: String) -> Option<String> {
    let value = value
        .trim()
        .chars()
        .filter(|character| {
            !character.is_control()
                && !matches!(
                    character,
                    '\u{061c}' | '\u{202a}'..='\u{202e}' | '\u{2066}'..='\u{2069}'
                )
        })
        .take(512)
        .collect::<String>();
    (!value.is_empty()).then_some(value)
}

fn paired_sso_peer(host: &PairedHost) -> PairedSsoPeer {
    PairedSsoPeer {
        statement_account_id: host.statement_account_id(),
        encryption_public_key: host.encryption_public_key(),
    }
}

fn persist_paired_host(session: &SigningHostSession, host: &PairedHost) -> Result<()> {
    if let Some(profile) = &session.profile {
        session.catalog.store_paired_host(profile, host.clone())?;
    }
    Ok(())
}

fn spawn_supervised_responder(
    runtime: Arc<SigningHostRuntime>,
    host: PairedHost,
    persisted: Option<(SessionCatalog, SessionProfile)>,
) -> tokio::task::JoinHandle<()> {
    tokio::spawn(async move {
        let peer = paired_sso_peer(&host);
        let mut retry_delay = std::time::Duration::from_secs(1);
        loop {
            let result = runtime.resume_pairing(peer).await;
            match result {
                Ok(ResponderExit::PeerDisconnected) => {
                    if let Some((catalog, profile)) = &persisted {
                        loop {
                            match catalog.remove_paired_host(profile, &peer.statement_account_id) {
                                Ok(_) => break,
                                Err(error) => {
                                    terminal_ui::output_event(SystemEvent::SigningHostError {
                                        reason: format!(
                                            "failed to remove disconnected paired device: {error}"
                                        ),
                                    });
                                    tokio::time::sleep(retry_delay).await;
                                    retry_delay =
                                        (retry_delay * 2).min(std::time::Duration::from_secs(30));
                                }
                            }
                        }
                        if let Err(error) = runtime
                            .untrack_statement_renewal_account(&peer.statement_account_id)
                            .await
                        {
                            terminal_ui::output_event(SystemEvent::SigningHostError {
                                reason: format!(
                                    "failed to stop renewing disconnected paired device: {}",
                                    error.reason
                                ),
                            });
                        }
                    }
                    terminal_ui::output_event(SystemEvent::SigningHostExit {
                        outcome: format!("{:?}", ResponderExit::PeerDisconnected),
                    });
                    return;
                }
                Ok(ResponderExit::SubscriptionEnded) => {
                    terminal_ui::output_event(SystemEvent::SigningHostExit {
                        outcome: format!("{:?}", ResponderExit::SubscriptionEnded),
                    });
                }
                Err(error) => {
                    terminal_ui::output_event(SystemEvent::SigningHostError {
                        reason: error.reason,
                    });
                }
            }
            tokio::time::sleep(retry_delay).await;
            retry_delay = (retry_delay * 2).min(std::time::Duration::from_secs(30));
        }
    })
}

fn start_paired_host_responder(session: &mut SigningHostSession, host: PairedHost) {
    let statement_account_id = host.statement_account_id();
    let persisted = session
        .profile
        .clone()
        .map(|profile| (session.catalog.clone(), profile));
    let task = spawn_supervised_responder(session.runtime.clone(), host, persisted);
    session.responders.insert(statement_account_id, task);
    terminal_ui::output_event(SystemEvent::SigningHostResponderStarted);
}

async fn restore_paired_responders(session: &mut SigningHostSession) {
    let Some(profile) = session.profile.clone() else {
        return;
    };
    let paired_hosts = match session.catalog.paired_hosts(&profile) {
        Ok(paired_hosts) => paired_hosts,
        Err(error) => {
            tracing::warn!(%error, "failed to read saved paired devices");
            return;
        }
    };
    if paired_hosts.is_empty() {
        return;
    }
    if let Err(error) = ensure_signer(session).await {
        tracing::warn!(%error, "failed to activate the signer for saved paired devices");
        return;
    }
    let mut renewal_targets = vec![StatementRenewalTarget::WalletSso];
    renewal_targets.extend(
        paired_hosts
            .iter()
            .map(|host| pairing_device_renewal_target(host.statement_account_id())),
    );
    if let Err(error) = session
        .runtime
        .track_statement_renewal_targets(renewal_targets)
        .await
    {
        tracing::warn!(
            reason = %error.reason,
            "failed to restore paired-device allowance renewal"
        );
    }
    for paired_host in paired_hosts {
        start_paired_host_responder(session, paired_host);
    }
}

/// Park until the operator stops the process. Ctrl-C is awaited so the host owns
/// its own shutdown; SIGTERM keeps its default action and ends the process.
async fn wait_for_shutdown() {
    if let Err(error) = tokio::signal::ctrl_c().await {
        // Nothing to await without a signal handler, so stay up and serve until
        // the process is killed rather than exiting as soon as it starts.
        terminal_ui::output_event(SystemEvent::SigningHostError {
            reason: format!("ctrl-c handling unavailable: {error}"),
        });
        std::future::pending::<()>().await;
    }
}

async fn ensure_signer(session: &mut SigningHostSession) -> Result<()> {
    if session.signer.is_some() {
        return Ok(());
    }
    let profile = session
        .profile
        .clone()
        .unwrap_or(session.catalog.profile(DEFAULT_SESSION_NAME)?);
    let account = (profile.name == DEFAULT_SESSION_NAME)
        .then(|| session.default_account.clone())
        .flatten();
    let lite_username_prefix =
        sessions::lite_username_prefix(&profile.name, session.lite_username_prefix.as_deref());
    session.signer = Some(
        accounts::resolve_signer(ResolveSignerConfig {
            base_path: &profile.account_base_path,
            network: session.network,
            mnemonic: session.mnemonic.clone(),
            account,
            lite_username_prefix,
            reserved_username: session.reserved_username.clone(),
        })
        .await?,
    );
    if let Err(error) = promote_current_profile(session) {
        session.signer = None;
        return Err(error);
    }
    if let Err(error) = activate_current_signer(session).await {
        session.signer = None;
        return Err(error);
    }
    Ok(())
}

fn promote_current_profile(session: &mut SigningHostSession) -> Result<()> {
    let Some(user_id) = session
        .signer
        .as_ref()
        .and_then(|signer| signer.lite_username.clone())
    else {
        return Ok(());
    };
    let Some(current) = session.profile.as_ref() else {
        return Ok(());
    };
    if current.name == user_id {
        return Ok(());
    }
    let promoted = session.catalog.promote_to_user(current, &user_id)?;
    let last_script = session.catalog.last_script(&promoted)?;
    let runtime = build_signing_runtime(
        session.network,
        promoted.path.clone(),
        promoted.product_storage_dir.clone(),
        session.approval,
        session.ui.clone(),
        session.chat.clone(),
    )?;
    session.runtime_factory.replace(runtime.clone());
    session.runtime = runtime;
    session.last_script = last_script;
    session.profile = Some(promoted);
    session.catalog.set_current(&user_id)?;
    if let Some(ui) = &session.ui {
        ui.session(user_id, session.catalog.list()?);
    }
    Ok(())
}

fn current_account_base_path(session: &SigningHostSession) -> Result<PathBuf> {
    Ok(session
        .profile
        .as_ref()
        .map(|profile| profile.account_base_path.clone())
        .unwrap_or(
            session
                .catalog
                .profile(DEFAULT_SESSION_NAME)?
                .account_base_path,
        ))
}

async fn activate_current_signer(session: &mut SigningHostSession) -> Result<()> {
    let signer = session
        .signer
        .as_ref()
        .context("signer has not been resolved")?;
    session
        .runtime
        .activate_local_session_with_identity(signer.entropy.clone(), signer.lite_username.clone())
        .await
        .map_err(|err| anyhow::anyhow!("failed to activate local session: {}", err.reason))?;
    if let (Some(profile), Some(user_id)) = (&session.profile, &signer.lite_username) {
        if let Some(account_name) = &signer.account_name {
            session
                .catalog
                .store_signer_binding(profile, user_id, account_name)?;
        } else {
            session.catalog.store_user_id(profile, user_id)?;
        }
        session.cached_user_id = Some(user_id.clone());
        if let Some(ui) = &session.ui {
            ui.connection(user_id.clone());
        }
    }
    terminal_ui::output_event(SystemEvent::SigningHostReady);
    Ok(())
}

async fn prepare_pairing_response(
    session: &mut SigningHostSession,
    candidate: &PairedHost,
    existing: &[PairedHost],
) -> Result<()> {
    let mut attempts = 0usize;
    loop {
        ensure_signer(session).await?;
        let (auto_managed, account_name) = {
            let signer = session
                .signer
                .as_ref()
                .context("signer has not been resolved")?;
            (signer.auto_managed, signer.account_name.clone())
        };
        match renew_pairing_allowances(session, existing, candidate).await {
            Ok(()) => return Ok(()),
            Err(err)
                if signer_identity_may_rotate(auto_managed, existing.len())
                    && is_statement_slot_exhaustion(&err) =>
            {
                attempts += 1;
                if attempts > 8 {
                    return Err(err);
                }
                if let Some(name) = &account_name {
                    let period = accounts::current_statement_period()?;
                    let account_base_path = current_account_base_path(session)?;
                    accounts::mark_account_exhausted(
                        &account_base_path,
                        session.network.id,
                        name,
                        period,
                    )?;
                    terminal_ui::output_event(SystemEvent::SigningHostAccountExhausted {
                        name: name.clone(),
                        period,
                    });
                }
                let account_base_path = current_account_base_path(session)?;
                let session_name = session
                    .profile
                    .as_ref()
                    .map_or(DEFAULT_SESSION_NAME, |profile| profile.name.as_str());
                let lite_username_prefix = sessions::lite_username_prefix(
                    session_name,
                    session.lite_username_prefix.as_deref(),
                );
                session.signer = Some(
                    accounts::resolve_signer(ResolveSignerConfig {
                        base_path: &account_base_path,
                        network: session.network,
                        mnemonic: None,
                        account: None,
                        lite_username_prefix,
                        reserved_username: session.reserved_username.clone(),
                    })
                    .await?,
                );
                activate_current_signer(session).await?;
            }
            Err(err) if !existing.is_empty() && is_statement_slot_exhaustion(&err) => {
                return Err(err).context(
                    "cannot pair another device without replacing an existing pairing; remove a paired device or wait for a new allowance period",
                );
            }
            Err(err) => return Err(err),
        }
    }
}

async fn establish_paired_host(
    session: &mut SigningHostSession,
    deeplink: &str,
) -> Result<PairedHost> {
    let candidate = paired_host_from_deeplink(deeplink)?;
    let existing = session
        .profile
        .as_ref()
        .map(|profile| session.catalog.paired_hosts(profile))
        .transpose()?
        .unwrap_or_default();
    let candidate_is_existing = existing
        .iter()
        .any(|host| host.statement_account_id() == candidate.statement_account_id());
    if let Err(error) = prepare_pairing_response(session, &candidate, &existing).await {
        discard_new_pairing_candidate(session, &candidate, candidate_is_existing).await;
        return Err(error);
    }

    let result = async {
        session
            .runtime
            .establish_pairing(deeplink)
            .await
            .map_err(|error| anyhow::anyhow!("pairing failed: {}", error.reason))?;
        persist_paired_host(session, &candidate)
    }
    .await;
    if let Err(error) = result {
        discard_new_pairing_candidate(session, &candidate, candidate_is_existing).await;
        return Err(error);
    }
    Ok(candidate)
}

async fn discard_new_pairing_candidate(
    session: &SigningHostSession,
    candidate: &PairedHost,
    candidate_is_existing: bool,
) {
    if !candidate_is_existing
        && let Err(error) = session
            .runtime
            .untrack_statement_renewal_account(&candidate.statement_account_id())
            .await
    {
        tracing::warn!(
            reason = %error.reason,
            "failed to discard abandoned pairing allowance renewal"
        );
    }
}

fn is_statement_slot_exhaustion(err: &anyhow::Error) -> bool {
    truapi_server::reports_exhausted_period(&err.to_string())
}

fn signer_identity_may_rotate(auto_managed: bool, paired_host_count: usize) -> bool {
    auto_managed && paired_host_count == 0
}

fn pairing_device_renewal_target(statement_account_id: [u8; 32]) -> StatementRenewalTarget {
    StatementRenewalTarget::Account {
        account_id: statement_account_id,
        label: format!("device:0x{}", hex::encode(statement_account_id)),
    }
}

async fn renew_pairing_allowances(
    session: &SigningHostSession,
    existing: &[PairedHost],
    candidate: &PairedHost,
) -> Result<()> {
    use truapi_server::statement_allowance::renewal::TargetRenewalStatus;

    let candidate_id = candidate.statement_account_id();
    let candidate_is_existing = existing
        .iter()
        .any(|host| host.statement_account_id() == candidate_id);
    let mut required_device_ids = existing
        .iter()
        .map(PairedHost::statement_account_id)
        .collect::<Vec<_>>();
    if !candidate_is_existing {
        required_device_ids.push(candidate_id);
    }
    required_device_ids.sort();
    required_device_ids.dedup();

    let mut targets = vec![StatementRenewalTarget::WalletSso];
    targets.extend(
        required_device_ids
            .iter()
            .copied()
            .map(pairing_device_renewal_target),
    );
    session
        .runtime
        .track_statement_renewal_targets(targets)
        .await
        .map_err(|error| {
            anyhow::anyhow!("failed to record pairing allowances: {}", error.reason)
        })?;
    let report = match session.runtime.renew_statement_allowances().await {
        Ok(report) => report,
        Err(error) => {
            if !candidate_is_existing {
                let _ = session
                    .runtime
                    .untrack_statement_renewal_account(&candidate_id)
                    .await;
            }
            bail!("pairing allowance renewal failed: {}", error.reason);
        }
    };

    let mut required_labels = vec!["wallet-sso".to_string()];
    required_labels.extend(
        required_device_ids
            .iter()
            .map(|account_id| format!("device:0x{}", hex::encode(account_id))),
    );
    for label in required_labels {
        let status = report
            .outcomes
            .iter()
            .rev()
            .find(|outcome| outcome.label == label)
            .map(|outcome| &outcome.status)
            .with_context(|| format!("pairing allowance renewal omitted {label}"))?;
        match status {
            TargetRenewalStatus::Registered { .. }
            | TargetRenewalStatus::AlreadyAllocated { .. } => {}
            TargetRenewalStatus::Failed { reason } => {
                if !candidate_is_existing {
                    let _ = session
                        .runtime
                        .untrack_statement_renewal_account(&candidate_id)
                        .await;
                }
                bail!("pairing allowance renewal for {label} failed: {reason}");
            }
            TargetRenewalStatus::SkippedExhausted => {
                if !candidate_is_existing {
                    let _ = session
                        .runtime
                        .untrack_statement_renewal_account(&candidate_id)
                        .await;
                }
                bail!("no free StatementStore slot for {label}");
            }
        }
    }
    Ok(())
}

/// Renew tracked statement-store allowances now, reporting each target.
async fn run_renew(session: &mut SigningHostSession) -> Result<()> {
    use truapi_server::statement_allowance::renewal::TargetRenewalStatus;

    ensure_signer(session).await?;
    let report = session
        .runtime
        .renew_statement_allowances()
        .await
        .map_err(|err| anyhow::anyhow!("allowance renewal failed: {}", err.reason))?;

    let (mut renewed, mut fresh, mut failed, mut skipped) = (0usize, 0usize, 0usize, 0usize);
    for outcome in &report.outcomes {
        let target = &outcome.label;
        match &outcome.status {
            TargetRenewalStatus::Registered { seq, block_hash } => {
                renewed += 1;
                terminal_ui::output_event(SystemEvent::AllowanceReady {
                    target: target.clone(),
                    sequence: *seq,
                    block_hash: Some(block_hash.clone()),
                    already_allocated: false,
                });
            }
            TargetRenewalStatus::AlreadyAllocated { seq } => {
                fresh += 1;
                terminal_ui::output_event(SystemEvent::AllowanceReady {
                    target: target.clone(),
                    sequence: *seq,
                    block_hash: None,
                    already_allocated: true,
                });
            }
            TargetRenewalStatus::Failed { reason } => {
                failed += 1;
                terminal_ui::output_event(SystemEvent::AllowanceRenewalFailed {
                    target: target.clone(),
                    reason: reason.clone(),
                });
            }
            TargetRenewalStatus::SkippedExhausted => skipped += 1,
        }
    }
    for label in &report.pruned {
        terminal_ui::output_event(SystemEvent::AllowanceRenewalPruned {
            target: label.clone(),
        });
    }
    terminal_ui::output_event(SystemEvent::AllowanceRenewalReport {
        period: report.period,
        renewed,
        fresh,
        failed,
        skipped,
        pruned: report.pruned.len(),
    });

    if report.slots_exhausted {
        let has_paired_hosts = session
            .profile
            .as_ref()
            .map(|profile| session.catalog.paired_hosts(profile))
            .transpose()?
            .is_some_and(|paired_hosts| !paired_hosts.is_empty());
        if has_paired_hosts {
            tracing::warn!(
                "statement-store slots are exhausted; preserving the signer because paired devices depend on its identity"
            );
        } else {
            mark_current_account_exhausted(session)?;
        }
    }
    Ok(())
}

fn mark_current_account_exhausted(session: &SigningHostSession) -> Result<()> {
    let Some(signer) = session.signer.as_ref() else {
        return Ok(());
    };
    if !signer.auto_managed {
        return Ok(());
    }
    let Some(name) = signer.account_name.clone() else {
        return Ok(());
    };
    let period = accounts::current_statement_period()?;
    let account_base_path = current_account_base_path(session)?;
    accounts::mark_account_exhausted(&account_base_path, session.network.id, &name, period)?;
    terminal_ui::output_event(SystemEvent::SigningHostAccountExhausted { name, period });
    Ok(())
}

async fn respond_to_deeplink(session: &mut SigningHostSession, deeplink: String) -> Result<()> {
    let host = establish_paired_host(session, &deeplink).await?;
    let statement_account_id = host.statement_account_id();
    let exit = session
        .runtime
        .resume_pairing(paired_sso_peer(&host))
        .await
        .map_err(|err| anyhow::anyhow!("pairing failed: {}", err.reason))?;
    if exit == ResponderExit::PeerDisconnected && session.profile.is_some() {
        remove_paired_host(session, &statement_account_id).await?;
    }
    terminal_ui::output_event(SystemEvent::SigningHostExit {
        outcome: format!("{exit:?}"),
    });
    Ok(())
}

async fn start_deeplink_responder(
    session: &mut SigningHostSession,
    deeplink: String,
) -> Result<()> {
    let host = establish_paired_host(session, &deeplink).await?;
    start_paired_host_responder(session, host);
    Ok(())
}

async fn remove_paired_host(
    session: &mut SigningHostSession,
    statement_account_id: &[u8; 32],
) -> Result<PairedHost> {
    let profile = session
        .profile
        .as_ref()
        .context("paired-device management is unavailable when launched with --mnemonic")?;
    let paired_host = session
        .catalog
        .paired_hosts(profile)?
        .into_iter()
        .find(|host| host.statement_account_id() == *statement_account_id)
        .with_context(|| {
            format!(
                "paired device 0x{} does not exist in session {}; use /devices to list paired devices",
                hex::encode(statement_account_id),
                profile.name
            )
        })?;
    session
        .catalog
        .remove_paired_host(profile, statement_account_id)?;
    session.responders.remove(statement_account_id);
    if let Err(error) = session
        .runtime
        .untrack_statement_renewal_account(statement_account_id)
        .await
    {
        tracing::warn!(
            reason = %error.reason,
            "paired device was removed, but its allowance renewal could not be removed"
        );
    }
    Ok(paired_host)
}

fn validate_session_clear(
    session: &SigningHostSession,
    target: &SessionClearTarget,
) -> Result<bool> {
    if session.mnemonic.is_some() {
        bail!("session clearing is unavailable when launched with --mnemonic");
    }
    session.catalog.validate_clear_target(target)?;
    Ok(match target {
        SessionClearTarget::All => true,
        SessionClearTarget::Named(name) => session
            .profile
            .as_ref()
            .is_some_and(|profile| profile.name == *name),
    })
}

fn session_clear_confirmation(
    session: &SigningHostSession,
    target: &SessionClearTarget,
    active: bool,
) -> (String, String) {
    let action = match target {
        SessionClearTarget::Named(name) => format!("Clear session {name}"),
        SessionClearTarget::All => {
            format!("Clear all sessions for {}", session.catalog.network_id())
        }
    };
    let scope = match target {
        SessionClearTarget::Named(_) => {
            "This permanently deletes its local signer keys, scripts, storage, and permissions"
        }
        SessionClearTarget::All => {
            "This permanently deletes every local session's signer keys, scripts, storage, and permissions"
        }
    };
    let mut detail = format!(
        "{scope} for {}. On-chain usernames are not removed.",
        session.catalog.network_id()
    );
    if active {
        detail.push_str(" The active session is included, so the signing host will stop.");
    }
    (action, detail)
}

fn session_clear_success(
    network_id: &str,
    target: &SessionClearTarget,
    stopped: bool,
) -> (String, String) {
    let title = match target {
        SessionClearTarget::Named(name) => format!("Session {name} cleared"),
        SessionClearTarget::All => format!("All sessions cleared for {network_id}"),
    };
    let detail = if stopped {
        "Signing host stopped. Restart it to create or select another session.".to_string()
    } else {
        format!(
            "Local signer keys, scripts, storage, and permissions were deleted for {network_id}."
        )
    };
    (title, detail)
}

fn clear_sessions_after_shutdown(
    catalog: &SessionCatalog,
    target: &SessionClearTarget,
) -> Result<()> {
    catalog.clear(target)?;
    let (title, detail) = session_clear_success(catalog.network_id(), target, true);
    terminal_ui::output_success(title, Some(detail));
    Ok(())
}

fn session_status_event(session: &SigningHostSession) -> SystemEvent {
    let name = session
        .profile
        .as_ref()
        .map_or("ephemeral", |profile| profile.name.as_str());
    let path = session.profile.as_ref().map_or_else(
        || "<none>".to_string(),
        |profile| profile.path.display().to_string(),
    );
    let user_id = session
        .signer
        .as_ref()
        .and_then(|signer| signer.lite_username.as_deref())
        .or(session.cached_user_id.as_deref())
        .unwrap_or_else(|| {
            if session.signer.is_some() {
                "<no assigned username>"
            } else {
                "<not provisioned>"
            }
        });
    SystemEvent::SessionStatus {
        name: name.to_string(),
        path,
        user_id: user_id.to_string(),
    }
}

fn session_status(session: &SigningHostSession) -> String {
    session_status_event(session).human()
}

fn session_list(session: &SigningHostSession) -> Result<String> {
    let current = session
        .profile
        .as_ref()
        .map_or("ephemeral", |profile| profile.name.as_str());
    let mut lines = vec!["Sessions".to_string()];
    for name in session.catalog.list()? {
        let marker = if name == current { "*" } else { " " };
        let path = session.catalog.profile(&name)?.path;
        lines.push(format!("{marker} {name}  {}", path.display()));
    }
    if lines.len() == 1 && session.profile.is_some() {
        lines.push("  <none>".to_string());
    }
    if session.profile.is_none() {
        lines.push("* ephemeral  <none>".to_string());
    }
    Ok(lines.join("\n"))
}

fn paired_device_label(host: &PairedHost) -> String {
    let metadata = host.metadata();
    let mut parts = Vec::new();
    if let Some(name) = &metadata.host_name {
        parts.push(name.clone());
    }
    if let Some(version) = &metadata.host_version {
        parts.push(version.clone());
    }
    let platform = match (&metadata.platform_type, &metadata.platform_version) {
        (Some(platform), Some(version)) => Some(format!("{platform} {version}")),
        (Some(platform), None) => Some(platform.clone()),
        (None, Some(version)) => Some(version.clone()),
        (None, None) => None,
    };
    if let Some(platform) = platform {
        parts.push(platform);
    }
    if parts.is_empty() {
        "<unknown device>".to_string()
    } else {
        parts.join(" · ")
    }
}

fn paired_device_list(session: &SigningHostSession) -> Result<String> {
    let profile = session
        .profile
        .as_ref()
        .context("paired-device management is unavailable when launched with --mnemonic")?;
    Ok(format_paired_device_list(
        &profile.name,
        session.catalog.paired_hosts(profile)?,
    ))
}

fn format_paired_device_list(session_name: &str, mut paired_hosts: Vec<PairedHost>) -> String {
    paired_hosts.sort_by_key(PairedHost::statement_account_id);
    if paired_hosts.is_empty() {
        return format!("No paired devices for session {session_name}");
    }
    let mut lines = vec![format!("Paired devices for session {session_name}")];
    lines.extend(paired_hosts.iter().map(|host| {
        format!(
            "0x{}  {}",
            hex::encode(host.statement_account_id()),
            paired_device_label(host)
        )
    }));
    lines.join("\n")
}

fn paired_device_remove_confirmation(
    session: &SigningHostSession,
    statement_account_id: &[u8; 32],
) -> Result<(String, String)> {
    let profile = session
        .profile
        .as_ref()
        .context("paired-device management is unavailable when launched with --mnemonic")?;
    let host = session
        .catalog
        .paired_hosts(profile)?
        .into_iter()
        .find(|host| host.statement_account_id() == *statement_account_id)
        .with_context(|| {
            format!(
                "paired device 0x{} does not exist in session {}; use /devices to list paired devices",
                hex::encode(statement_account_id),
                profile.name
            )
        })?;
    Ok((
        format!("Remove paired device {}", paired_device_label(&host)),
        format!(
            "Statement account 0x{}. This stops its responder and removes its saved pairing from session {}. Other paired devices and the signing identity are unchanged. The remote host must pair again.",
            hex::encode(statement_account_id),
            profile.name
        ),
    ))
}

async fn switch_session(session: &mut SigningHostSession, name: String) -> Result<()> {
    if session.mnemonic.is_some() {
        bail!("session switching is unavailable when launched with --mnemonic");
    }
    sessions::validate_selectable_name(&name).map_err(anyhow::Error::msg)?;
    if session
        .profile
        .as_ref()
        .is_some_and(|profile| profile.name == name)
    {
        terminal_ui::output_event(session_status_event(session));
        return Ok(());
    }

    let existed = session.catalog.exists(&name);
    let old_name = session
        .profile
        .as_ref()
        .map_or(DEFAULT_SESSION_NAME, |profile| profile.name.as_str())
        .to_string();
    if existed {
        terminal_ui::output_event(SystemEvent::SessionSwitching {
            from: old_name.clone(),
            to: name.clone(),
        });
    } else {
        terminal_ui::output_event(SystemEvent::SessionCreating { name: name.clone() });
    }

    // Resolve and provision the target completely while the old runtime keeps
    // serving. Only the final runtime replacement invalidates product sockets.
    let provisional_profile = session.catalog.ensure_profile(&name)?;
    let lite_username_prefix =
        sessions::lite_username_prefix(&name, session.lite_username_prefix.as_deref());
    let signer = accounts::resolve_signer(ResolveSignerConfig {
        base_path: &provisional_profile.account_base_path,
        network: session.network,
        mnemonic: None,
        account: if name == DEFAULT_SESSION_NAME {
            session.default_account.clone()
        } else {
            None
        },
        lite_username_prefix,
        reserved_username: session.reserved_username.clone(),
    })
    .await?;
    let profile = if let Some(user_id) = &signer.lite_username {
        session
            .catalog
            .promote_to_user(&provisional_profile, user_id)?
    } else {
        provisional_profile
    };
    let last_script = session.catalog.last_script(&profile)?;
    let runtime = build_signing_runtime(
        session.network,
        profile.path.clone(),
        profile.product_storage_dir.clone(),
        session.approval,
        session.ui.clone(),
        session.chat.clone(),
    )?;
    let available_sessions = session.catalog.list()?;

    if let Err(error) = runtime
        .activate_local_session_with_identity(signer.entropy.clone(), signer.lite_username.clone())
        .await
    {
        bail!("failed to activate session {name:?}: {}", error.reason);
    }
    if let (Some(user_id), Some(account_name)) = (&signer.lite_username, &signer.account_name) {
        session
            .catalog
            .store_signer_binding(&profile, user_id, account_name)?;
    }
    session.catalog.set_current(&profile.name)?;

    session.responders.stop_all();
    session.runtime_factory.replace(runtime.clone());
    session.runtime = runtime;
    session.cached_user_id = signer.lite_username.clone();
    session.signer = Some(signer);
    session.last_script = last_script;
    session.profile = Some(profile);
    if let Some(ui) = &session.ui {
        let current_name = session
            .profile
            .as_ref()
            .map(|profile| profile.name.clone())
            .unwrap_or(name);
        ui.session(current_name, available_sessions);
        if let Some(user_id) = &session.cached_user_id {
            ui.connection(user_id.clone());
        }
    }
    terminal_ui::output_event(session_status_event(session));
    restore_paired_responders(session).await;
    Ok(())
}

/// Import an existing mnemonic as a durable session, using its existing
/// identity username when one exists and a key fingerprint otherwise.
/// Inspection and runtime activation happen before the secret is committed
/// locally, so the current session keeps serving on failure.
async fn import_mnemonic_session(
    session: &mut SigningHostSession,
    mnemonic: &crate::signing_shell::SecretMnemonic,
) -> Result<()> {
    if session.mnemonic.is_some() {
        bail!("session import is unavailable when launched with --mnemonic");
    }

    terminal_ui::update_activity(
        "signer",
        "Importing signer",
        Some("Checking identity and ring membership".to_string()),
        ActivityState::Running,
    );
    let imported =
        accounts::inspect_imported_signer(session.network, mnemonic.expose_secret()).await?;
    let username = imported.username().map(str::to_string);
    let session_name = imported.session_name().to_string();
    sessions::validate_selectable_name(&session_name).map_err(anyhow::Error::msg)?;

    let old_name = session
        .profile
        .as_ref()
        .map_or(DEFAULT_SESSION_NAME, |profile| profile.name.as_str())
        .to_string();
    if session.catalog.exists(&session_name) {
        terminal_ui::output_event(SystemEvent::SessionSwitching {
            from: old_name,
            to: session_name.clone(),
        });
    } else {
        terminal_ui::output_event(SystemEvent::SessionCreating {
            name: session_name.clone(),
        });
    }

    let profile = session.catalog.ensure_profile(&session_name)?;
    let last_script = session.catalog.last_script(&profile)?;
    let runtime = build_signing_runtime(
        session.network,
        profile.path.clone(),
        profile.product_storage_dir.clone(),
        session.approval,
        session.ui.clone(),
        session.chat.clone(),
    )?;
    runtime
        .activate_local_session_with_identity(imported.entropy().to_vec(), username.clone())
        .await
        .map_err(|error| {
            anyhow::anyhow!(
                "failed to activate imported session {session_name:?}: {}",
                error.reason
            )
        })?;

    let signer = accounts::persist_imported_signer(
        &profile.account_base_path,
        session.network.id,
        &imported,
    )?;
    let account_name = signer
        .account_name
        .as_deref()
        .context("imported signer has no stored account name")?;
    if let Some(username) = &username {
        session
            .catalog
            .store_signer_binding(&profile, username, account_name)?;
    } else {
        session
            .catalog
            .store_account_binding(&profile, account_name)?;
    }
    session.catalog.set_current(&session_name)?;
    let available_sessions = session.catalog.list()?;

    session.responders.stop_all();
    session.runtime_factory.replace(runtime.clone());
    session.runtime = runtime;
    session.cached_user_id = username.clone();
    session.signer = Some(signer);
    session.last_script = last_script;
    session.profile = Some(profile);
    if let Some(ui) = &session.ui {
        ui.session(session_name.clone(), available_sessions);
        if let Some(username) = &username {
            ui.connection(username.clone());
        }
    }
    let detail = username.as_ref().map_or_else(
        || {
            "The account is connected by key; it has no assigned username on this network."
                .to_string()
        },
        |username| format!("Connected as identity user {username}."),
    );
    terminal_ui::output_success(format!("Imported session {session_name}"), Some(detail));
    let activity_detail = username.map_or_else(
        || "connected by account key (no assigned username)".to_string(),
        |username| format!("identity username {username}"),
    );
    terminal_ui::update_activity(
        "signer",
        "Imported signer",
        Some(activity_detail),
        ActivityState::Succeeded,
    );
    terminal_ui::output_event(session_status_event(session));
    restore_paired_responders(session).await;
    Ok(())
}

async fn pairing_interactive_loop(
    frame_url: String,
    product: Arc<frame_server::ProductSelection>,
    runtime: Arc<PairingHostRuntime>,
    storage: Arc<CliPlatform>,
    mut ui: ActiveTerminalUi,
    log_controller: LogController,
) -> Result<()> {
    let mut pairing_state_path = storage
        .state_dir()
        .context("pairing host storage is not configured")?;
    let mut last_script = sessions::session_last_script(&pairing_state_path)?;
    loop {
        let Some(input) = ui.next_command().await? else {
            return Ok(());
        };
        ui.command(input.clone());
        let command = match parse_command(&input) {
            Ok(command) => command,
            Err(error) => {
                ui.error(error);
                continue;
            }
        };
        match command {
            ShellCommand::Help => ui.system(PAIRING_HELP_TEXT),
            ShellCommand::Clear => ui.clear(),
            ShellCommand::Copy => match ui.copy_transcript() {
                Ok(entries) => ui.event(SystemEvent::CopiedTranscript { entries }),
                Err(error) => ui.error(format!("failed to copy transcript: {error}")),
            },
            ShellCommand::Login => {
                let product_id = product.current();
                run_pairing_login(&runtime, &product_id, input, &mut ui).await?;
            }
            ShellCommand::Logout => match runtime.logout().await {
                Ok(()) => ui.success(
                    "Logged out",
                    Some(
                        "The next product login will generate new pairing keys and a fresh link."
                            .to_string(),
                    ),
                ),
                Err(error) => ui.error(format!("logout failed: {}", error.reason)),
            },
            ShellCommand::Log(level) => {
                if let Err(error) = log_controller.set(level) {
                    ui.error(format!("failed to set log level: {error}"));
                } else {
                    ui.set_log_level(level);
                    ui.event(SystemEvent::LogLevelChanged { level });
                }
            }
            ShellCommand::Product(ProductCommand::Current) => ui.system(product.current()),
            ShellCommand::Product(ProductCommand::Switch(product_id)) => {
                match product.select(product_id) {
                    Ok(true) => {
                        let product_id = product.current();
                        ui.set_product(product_id.clone());
                        ui.success(
                            format!("Product set to {product_id}"),
                            Some("Reconnect product clients to continue.".to_string()),
                        );
                    }
                    Ok(false) => ui.system(product.current()),
                    Err(error) => ui.error(error.to_string()),
                }
            }
            ShellCommand::Quit => return Ok(()),
            ShellCommand::Script(script) => {
                let current_state_path = storage
                    .state_dir()
                    .context("pairing host storage is not configured")?;
                if current_state_path != pairing_state_path {
                    pairing_state_path = current_state_path;
                    last_script = sessions::session_last_script(&pairing_state_path)?;
                }
                let scratch_script_directory = pairing_state_path.join("scripts");
                let script = match script {
                    Some(script) => {
                        remember_script(Some(&pairing_state_path), &mut last_script, script)
                    }
                    None => {
                        let script =
                            select_script_to_edit(&scratch_script_directory, &mut last_script);
                        match script {
                            Ok(script) => match sessions::store_session_last_script(
                                &pairing_state_path,
                                &script,
                            ) {
                                Ok(()) => edit_script_in(script, &mut ui).await,
                                Err(error) => Err(error),
                            },
                            Err(error) => Err(error),
                        }
                    }
                };
                match script {
                    Ok(script) => {
                        let product_id = product.current();
                        run_pairing_script(&frame_url, &product_id, &script, input, &mut ui)
                            .await?;
                    }
                    Err(error) => ui.error(error.to_string()),
                }
            }
            ShellCommand::Pair(_)
            | ShellCommand::Devices(_)
            | ShellCommand::Session(_)
            | ShellCommand::Renew => {
                ui.error("command is only available on the signing host");
            }
        }
    }
}

async fn run_pairing_login(
    runtime: &PairingHostRuntime,
    product_id: &str,
    label: String,
    ui: &mut ActiveTerminalUi,
) -> Result<()> {
    let checkpoint = ui.activity_checkpoint();
    match ui
        .drive_pairing_login(label, runtime.login(product_id))
        .await?
    {
        DriveResult::Complete(Ok(truapi::v01::HostRequestLoginResponse::Success)) => {}
        DriveResult::Complete(Ok(truapi::v01::HostRequestLoginResponse::AlreadyConnected)) => {
            ui.success("Already logged in", None);
        }
        DriveResult::Complete(Ok(truapi::v01::HostRequestLoginResponse::Rejected)) => {
            ui.finish_activities_since(checkpoint, ActivityState::Cancelled, "Login was rejected");
            ui.error("login rejected");
        }
        DriveResult::Complete(Err(error)) => {
            ui.finish_activities_since(
                checkpoint,
                ActivityState::Failed,
                "Login stopped after an error",
            );
            ui.error(format!("login failed: {}", error.reason));
        }
        DriveResult::Cancelled => {
            runtime.cancel_pairing();
            ui.finish_activities_since(checkpoint, ActivityState::Cancelled, "Login cancelled");
            ui.error("login cancelled");
        }
    }
    Ok(())
}

async fn run_pairing_script(
    frame_url: &str,
    product_id: &str,
    script: &std::path::Path,
    label: String,
    ui: &mut ActiveTerminalUi,
) -> Result<()> {
    let activity_checkpoint = ui.activity_checkpoint();
    let handle = ui.handle();
    let operation = async {
        let status = script_runner::run_captured(
            frame_url,
            product_id,
            script,
            handle,
            script_runner::ScriptHostRole::PairingHost,
        )
        .await?;
        terminal_ui::output_event(SystemEvent::ScriptExit {
            code: status.code().unwrap_or(1),
        });
        Ok::<(), anyhow::Error>(())
    };
    match ui.drive(label, operation).await? {
        DriveResult::Complete(Ok(())) => {}
        DriveResult::Complete(Err(error)) => {
            ui.finish_activities_since(
                activity_checkpoint,
                ActivityState::Failed,
                "Stopped after an error",
            );
            ui.error(error.to_string());
        }
        DriveResult::Cancelled => {
            ui.finish_activities_since(activity_checkpoint, ActivityState::Cancelled, "Cancelled");
            ui.error("command cancelled");
        }
    }
    Ok(())
}

async fn signing_interactive_loop(
    session: &mut SigningHostSession,
    frame_url: String,
    product: Arc<frame_server::ProductSelection>,
    initial_deeplink: Option<String>,
    mut ui: ActiveTerminalUi,
    log_controller: LogController,
) -> Result<Option<SessionClearTarget>> {
    if let Some(deeplink) = initial_deeplink {
        let input = format!("/pair {deeplink}");
        ui.command(input.clone());
        let product_id = product.current();
        run_interactive_operation(
            session,
            &frame_url,
            &product_id,
            ShellCommand::Pair(deeplink),
            input,
            &mut ui,
        )
        .await?;
    }

    loop {
        let Some(input) = ui.next_command().await? else {
            return Ok(None);
        };
        ui.command(input.clone());
        let command = match parse_command(&input) {
            Ok(command) => command,
            Err(error) => {
                ui.error(error);
                continue;
            }
        };
        match command {
            ShellCommand::Help => ui.system(HELP_TEXT),
            ShellCommand::Clear => ui.clear(),
            ShellCommand::Copy => match ui.copy_transcript() {
                Ok(entries) => ui.event(SystemEvent::CopiedTranscript { entries }),
                Err(error) => ui.error(format!("failed to copy transcript: {error}")),
            },
            ShellCommand::Log(level) => {
                if let Err(error) = log_controller.set(level) {
                    ui.error(format!("failed to set log level: {error}"));
                } else {
                    ui.set_log_level(level);
                    ui.event(SystemEvent::LogLevelChanged { level });
                }
            }
            ShellCommand::Product(ProductCommand::Current) => ui.system(product.current()),
            ShellCommand::Product(ProductCommand::Switch(product_id)) => {
                match product.select(product_id) {
                    Ok(true) => {
                        let product_id = product.current();
                        ui.set_product(product_id.clone());
                        ui.success(
                            format!("Product set to {product_id}"),
                            Some("Reconnect product clients to continue.".to_string()),
                        );
                    }
                    Ok(false) => ui.system(product.current()),
                    Err(error) => ui.error(error.to_string()),
                }
            }
            ShellCommand::Session(SessionCommand::Current) => {
                ui.event(session_status_event(session));
                if session.profile.is_some() && session.signer.is_none() {
                    ui.event(SystemEvent::SigningHostNeedsSession);
                }
            }
            ShellCommand::Session(SessionCommand::List) => match session_list(session) {
                Ok(sessions) => ui.system(sessions),
                Err(error) => ui.error(format!("failed to list sessions: {error}")),
            },
            ShellCommand::Devices(DeviceCommand::List) => match paired_device_list(session) {
                Ok(devices) => ui.system(devices),
                Err(error) => ui.error(format!("failed to list paired devices: {error}")),
            },
            ShellCommand::Devices(DeviceCommand::Remove(statement_account_id)) => {
                let (action, detail) =
                    match paired_device_remove_confirmation(session, &statement_account_id) {
                        Ok(confirmation) => confirmation,
                        Err(error) => {
                            ui.error(error.to_string());
                            continue;
                        }
                    };
                let handle = ui.handle();
                let approved = match ui
                    .drive(input.clone(), handle.confirm(action, detail))
                    .await?
                {
                    DriveResult::Complete(approved) => approved,
                    DriveResult::Cancelled => false,
                };
                if !approved {
                    ui.system("Paired-device removal cancelled");
                    continue;
                }
                match remove_paired_host(session, &statement_account_id).await {
                    Ok(host) => ui.success(
                        "Paired device removed",
                        Some(format!(
                            "{}\nStatement account 0x{}",
                            paired_device_label(&host),
                            hex::encode(statement_account_id)
                        )),
                    ),
                    Err(error) => ui.error(error.to_string()),
                }
            }
            ShellCommand::Session(SessionCommand::Clear(target)) => {
                let active = match validate_session_clear(session, &target) {
                    Ok(active) => active,
                    Err(error) => {
                        ui.error(error.to_string());
                        continue;
                    }
                };
                let (action, detail) = session_clear_confirmation(session, &target, active);
                let handle = ui.handle();
                let approved = match ui
                    .drive(input.clone(), handle.confirm(action, detail))
                    .await?
                {
                    DriveResult::Complete(approved) => approved,
                    DriveResult::Cancelled => false,
                };
                if !approved {
                    ui.system("Session clear cancelled");
                    continue;
                }
                if active || target == SessionClearTarget::All {
                    session.responders.stop_all();
                    session.runtime_factory.reset_connections();
                    tokio::task::yield_now().await;
                    return Ok(Some(target));
                }
                match session.catalog.clear(&target) {
                    Ok(_) => {
                        let (title, detail) =
                            session_clear_success(session.catalog.network_id(), &target, false);
                        ui.success(title, Some(detail));
                        let current = session
                            .profile
                            .as_ref()
                            .map_or(DEFAULT_SESSION_NAME, |profile| profile.name.as_str());
                        ui.handle().session(current, session.catalog.list()?);
                    }
                    Err(error) => ui.error(error.to_string()),
                }
            }
            ShellCommand::Quit => return Ok(None),
            ShellCommand::Script(None) => match edit_session_script(session, &mut ui).await {
                Ok(script) => {
                    let product_id = product.current();
                    run_interactive_operation(
                        session,
                        &frame_url,
                        &product_id,
                        ShellCommand::Script(Some(script)),
                        input,
                        &mut ui,
                    )
                    .await?;
                }
                Err(error) => ui.error(error.to_string()),
            },
            command => {
                let product_id = product.current();
                run_interactive_operation(
                    session,
                    &frame_url,
                    &product_id,
                    command,
                    input,
                    &mut ui,
                )
                .await?;
            }
        }
    }
}

async fn run_interactive_operation(
    session: &mut SigningHostSession,
    frame_url: &str,
    product_id: &str,
    command: ShellCommand,
    label: String,
    ui: &mut ActiveTerminalUi,
) -> Result<()> {
    let activity_checkpoint = ui.activity_checkpoint();
    let handle = ui.handle();
    let operation = execute_interactive_operation(session, frame_url, product_id, command, handle);
    match ui.drive(label, operation).await? {
        DriveResult::Complete(Ok(())) => {}
        DriveResult::Complete(Err(error)) => {
            ui.finish_activities_since(
                activity_checkpoint,
                ActivityState::Failed,
                "Stopped after an error",
            );
            ui.error_with_causes(&error);
        }
        DriveResult::Cancelled => {
            ui.finish_activities_since(activity_checkpoint, ActivityState::Cancelled, "Cancelled");
            ui.error("command cancelled");
        }
    }
    Ok(())
}

async fn execute_interactive_operation(
    session: &mut SigningHostSession,
    frame_url: &str,
    product_id: &str,
    command: ShellCommand,
    ui: UiHandle,
) -> Result<()> {
    match command {
        ShellCommand::Pair(deeplink) => start_deeplink_responder(session, deeplink).await?,
        ShellCommand::Script(Some(script)) => {
            let session_path = session.profile.as_ref().map(|profile| profile.path.clone());
            let script =
                remember_script(session_path.as_deref(), &mut session.last_script, script)?;
            ensure_signer(session).await?;
            let status = script_runner::run_captured(
                frame_url,
                product_id,
                &script,
                ui,
                script_runner::ScriptHostRole::SigningHost,
            )
            .await?;
            terminal_ui::output_event(SystemEvent::ScriptExit {
                code: status.code().unwrap_or(1),
            });
        }
        ShellCommand::Script(None) => bail!("new scripts must be edited by the terminal UI"),
        ShellCommand::Session(SessionCommand::Switch(name)) => {
            switch_session(session, name).await?;
        }
        ShellCommand::Session(SessionCommand::ImportMnemonic(mnemonic)) => {
            import_mnemonic_session(session, &mnemonic).await?;
        }
        ShellCommand::Renew => run_renew(session).await?,
        ShellCommand::Login => bail!("/login is only available on the pairing host"),
        ShellCommand::Logout => bail!("/logout is only available on the pairing host"),
        ShellCommand::Product(_) | ShellCommand::Devices(_) => {
            bail!("command must be handled by the terminal UI")
        }
        ShellCommand::Help
        | ShellCommand::Clear
        | ShellCommand::Copy
        | ShellCommand::Log(_)
        | ShellCommand::Session(
            SessionCommand::Current | SessionCommand::List | SessionCommand::Clear(_),
        )
        | ShellCommand::Quit => {
            bail!("command must be handled by the terminal UI")
        }
    }
    Ok(())
}

async fn execute_non_interactive_command(
    session: &mut SigningHostSession,
    frame_url: &str,
    product: &frame_server::ProductSelection,
    command: ShellCommand,
    log_controller: &LogController,
) -> Result<Option<SessionClearTarget>> {
    match command {
        ShellCommand::Pair(deeplink) => respond_to_deeplink(session, deeplink).await?,
        ShellCommand::Script(script) => {
            let script = match script {
                Some(script) => {
                    let session_path = session.profile.as_ref().map(|profile| profile.path.clone());
                    remember_script(session_path.as_deref(), &mut session.last_script, script)?
                }
                None => edit_session_script_plain(session).await?,
            };
            ensure_signer(session).await?;
            let product_id = product.current();
            let status = script_runner::run(
                frame_url,
                &product_id,
                &script,
                script_runner::ScriptHostRole::SigningHost,
            )
            .await?;
            let code = status.code().unwrap_or(1);
            terminal_ui::output_event(SystemEvent::ScriptExit { code });
            if !status.success() {
                bail!("script exited with code {code}");
            }
        }
        ShellCommand::Help => println!("{HELP_TEXT}"),
        ShellCommand::Clear | ShellCommand::Quit => {}
        ShellCommand::Copy => bail!("/copy is only available in the terminal UI"),
        ShellCommand::Login => bail!("/login is only available on the pairing host"),
        ShellCommand::Logout => bail!("/logout is only available on the pairing host"),
        ShellCommand::Log(level) => {
            log_controller.set(level)?;
            terminal_ui::output_event(SystemEvent::LogLevelChanged { level });
        }
        ShellCommand::Product(ProductCommand::Current) => {
            println!("{}", product.current());
        }
        ShellCommand::Product(ProductCommand::Switch(product_id)) => {
            if product.select(product_id)? {
                terminal_ui::output_success(
                    format!("Product set to {}", product.current()),
                    Some("Reconnect product clients to continue.".to_string()),
                );
            } else {
                println!("{}", product.current());
            }
        }
        ShellCommand::Session(SessionCommand::Current) => {
            println!("{}", session_status(session));
            if session.profile.is_some() && session.signer.is_none() {
                terminal_ui::output_event(SystemEvent::SigningHostNeedsSession);
            }
        }
        ShellCommand::Session(SessionCommand::List) => {
            println!("{}", session_list(session)?);
        }
        ShellCommand::Devices(DeviceCommand::List) => {
            println!("{}", paired_device_list(session)?);
        }
        ShellCommand::Devices(DeviceCommand::Remove(statement_account_id)) => {
            let profile_name = session
                .profile
                .as_ref()
                .context("paired-device management is unavailable when launched with --mnemonic")?
                .name
                .clone();
            remove_paired_host(session, &statement_account_id).await?;
            println!(
                "Removed paired device 0x{} from session {}",
                hex::encode(statement_account_id),
                profile_name
            );
        }
        ShellCommand::Session(SessionCommand::Switch(name)) => {
            switch_session(session, name).await?;
        }
        ShellCommand::Session(SessionCommand::ImportMnemonic(mnemonic)) => {
            import_mnemonic_session(session, &mnemonic).await?;
        }
        ShellCommand::Session(SessionCommand::Clear(target)) => {
            validate_session_clear(session, &target)?;
            session.responders.stop_all();
            session.runtime_factory.reset_connections();
            tokio::task::yield_now().await;
            return Ok(Some(target));
        }
        ShellCommand::Renew => run_renew(session).await?,
    }
    Ok(None)
}

fn scratch_script_directory(session: &SigningHostSession) -> PathBuf {
    session.profile.as_ref().map_or_else(
        || std::env::temp_dir().join("truapi-host").join("scripts"),
        |profile| profile.path.join("scripts"),
    )
}

fn select_script_to_edit(
    scratch_script_directory: &std::path::Path,
    last_script: &mut Option<PathBuf>,
) -> Result<PathBuf> {
    if let Some(script) = last_script.as_ref().filter(|script| script.is_file()) {
        return Ok(script.clone());
    }
    let script = script_runner::create_scratch_script(scratch_script_directory)?;
    *last_script = Some(script.clone());
    Ok(script)
}

fn remember_script(
    session_path: Option<&std::path::Path>,
    last_script: &mut Option<PathBuf>,
    script: PathBuf,
) -> Result<PathBuf> {
    let script = if script.is_absolute() {
        script
    } else {
        std::env::current_dir()
            .context("resolve current directory for script")?
            .join(script)
    };
    if let Some(session_path) = session_path {
        sessions::store_session_last_script(session_path, &script)?;
    }
    *last_script = Some(script.clone());
    Ok(script)
}

fn session_script_to_edit(session: &mut SigningHostSession) -> Result<PathBuf> {
    let directory = scratch_script_directory(session);
    let script = select_script_to_edit(&directory, &mut session.last_script)?;
    if let Some(profile) = &session.profile {
        session.catalog.store_last_script(profile, &script)?;
    }
    Ok(script)
}

async fn edit_session_script(
    session: &mut SigningHostSession,
    ui: &mut ActiveTerminalUi,
) -> Result<PathBuf> {
    let script = session_script_to_edit(session)?;
    edit_script_in(script, ui).await
}

async fn edit_script_in(script: PathBuf, ui: &mut ActiveTerminalUi) -> Result<PathBuf> {
    ui.system(format!("Opening {} in your editor", script.display()));
    ui.suspend()?;
    let edit_result = script_runner::edit(&script).await;
    let resume_result = ui.resume();
    if let Err(error) = resume_result {
        return Err(error).context("restore terminal UI after editor");
    }
    let status = edit_result?;
    if !status.success() {
        bail!(
            "editor exited with {}; script retained at {}",
            status.code().unwrap_or(1),
            script.display()
        );
    }
    ui.success("Script saved", Some(script.display().to_string()));
    Ok(script)
}

async fn edit_session_script_plain(session: &mut SigningHostSession) -> Result<PathBuf> {
    if !terminal_ui::is_interactive_terminal() {
        bail!("/script without a path requires an interactive terminal");
    }
    let script = session_script_to_edit(session)?;
    eprintln!("EDITING_SCRIPT {}", script.display());
    let status = script_runner::edit(&script).await?;
    if !status.success() {
        bail!(
            "editor exited with {}; script retained at {}",
            status.code().unwrap_or(1),
            script.display()
        );
    }
    eprintln!("SAVED_SCRIPT {}", script.display());
    Ok(script)
}

fn default_base_path() -> PathBuf {
    if let Some(path) = std::env::var_os("XDG_STATE_HOME") {
        return PathBuf::from(path).join("truapi-host");
    }
    if let Some(home) = std::env::var_os("HOME") {
        return PathBuf::from(home).join(".local/state/truapi-host");
    }
    PathBuf::from(".truapi-host")
}

#[cfg(test)]
mod cli_tests {
    use super::*;
    use parity_scale_codec::Encode;

    #[test]
    fn pairing_deeplink_becomes_a_public_persistable_host_record() {
        use truapi_server::host_logic::sso::pairing::{
            VersionedHandshakeProposal,
            v2::{Device, MetadataEntry, MetadataKey, Proposal},
        };

        let proposal = VersionedHandshakeProposal::V2(Proposal {
            device: Device {
                statement_account_id: [1; 32],
                encryption_public_key: [2; 32],
            },
            metadata: vec![
                MetadataEntry(
                    MetadataKey::HostName,
                    " Desk\u{202e}top\u{2066}\nHost\u{061c} ".to_string(),
                ),
                MetadataEntry(MetadataKey::HostVersion, "1.2.3".to_string()),
            ],
        });
        let deeplink = format!(
            "polkadotapp://pair?handshake={}",
            hex::encode(proposal.encode())
        );

        assert_eq!(
            paired_host_from_deeplink(&deeplink).unwrap(),
            PairedHost::new(
                [1; 32],
                [2; 32],
                PairedHostMetadata {
                    host_name: Some("DesktopHost".to_string()),
                    host_version: Some("1.2.3".to_string()),
                    ..PairedHostMetadata::default()
                }
            )
        );
    }

    #[tokio::test]
    async fn responder_manager_keeps_unrelated_peers_and_replaces_only_the_same_peer() {
        let mut manager = ResponderManager::default();
        let first = tokio::spawn(std::future::pending::<()>());
        let first_abort = first.abort_handle();
        let second = tokio::spawn(std::future::pending::<()>());
        let second_abort = second.abort_handle();
        manager.insert([1; 32], first);
        manager.insert([2; 32], second);

        let replacement = tokio::spawn(std::future::pending::<()>());
        manager.insert([1; 32], replacement);
        tokio::task::yield_now().await;

        assert_eq!(
            (
                manager
                    .tasks
                    .keys()
                    .copied()
                    .collect::<std::collections::HashSet<_>>(),
                first_abort.is_finished(),
                second_abort.is_finished(),
            ),
            ([[1; 32], [2; 32]].into_iter().collect(), true, false,)
        );
    }

    #[tokio::test]
    async fn responder_manager_removes_only_the_selected_peer() {
        let mut manager = ResponderManager::default();
        let first = tokio::spawn(std::future::pending::<()>());
        let first_abort = first.abort_handle();
        let second = tokio::spawn(std::future::pending::<()>());
        let second_abort = second.abort_handle();
        manager.insert([1; 32], first);
        manager.insert([2; 32], second);

        assert!(manager.remove(&[1; 32]));
        tokio::task::yield_now().await;

        assert_eq!(
            (
                manager.tasks.keys().copied().collect::<Vec<_>>(),
                first_abort.is_finished(),
                second_abort.is_finished(),
            ),
            (vec![[2; 32]], true, false)
        );
    }

    #[test]
    fn paired_device_list_is_sorted_and_includes_available_display_metadata() {
        let named = PairedHost::new(
            [2; 32],
            [22; 32],
            PairedHostMetadata {
                host_name: Some("Desktop".to_string()),
                host_version: Some("1.2.3".to_string()),
                host_icon: None,
                platform_type: Some("macOS".to_string()),
                platform_version: Some("26.1".to_string()),
            },
        );
        let unknown = PairedHost::new([1; 32], [11; 32], PairedHostMetadata::default());

        assert_eq!(
            format_paired_device_list("alice.01", vec![named, unknown]),
            format!(
                "Paired devices for session alice.01\n0x{}  <unknown device>\n0x{}  Desktop · 1.2.3 · macOS 26.1",
                hex::encode([1; 32]),
                hex::encode([2; 32])
            )
        );
    }

    #[test]
    fn paired_device_list_reports_an_empty_session() {
        assert_eq!(
            format_paired_device_list("alice.01", Vec::new()),
            "No paired devices for session alice.01"
        );
    }

    #[test]
    fn an_auto_managed_signer_never_rotates_while_a_paired_host_depends_on_it() {
        assert!(signer_identity_may_rotate(true, 0));
        assert!(!signer_identity_may_rotate(true, 1));
        assert!(!signer_identity_may_rotate(true, 2));
        assert!(!signer_identity_may_rotate(false, 0));
    }

    #[test]
    fn trace_log_level_is_available_before_or_after_the_subcommand() {
        let before = Cli::try_parse_from(["truapi-host", "--log-level", "trace", "signing-host"])
            .expect("global log level before subcommand should parse");
        let after = Cli::try_parse_from(["truapi-host", "signing-host", "--log-level", "trace"])
            .expect("global log level after subcommand should parse");

        assert_eq!(before.log_level, LogLevel::Trace);
        assert_eq!(after.log_level, LogLevel::Trace);
        assert_eq!(LogLevel::Trace.as_filter(), "trace");
        assert_eq!(
            LogLevel::Trace.scoped_filter(),
            "warn,truapi=trace,truapi_host=trace,truapi_platform=trace,truapi_server=trace"
        );
    }

    #[test]
    fn noisy_transport_targets_are_always_excluded_from_cli_logs() {
        assert!(!log_target_is_visible(terminal_ui::SSO_TRANSCRIPT_TARGET));
        assert!(!log_target_is_visible("rustls"));
        assert!(!log_target_is_visible("rustls::client::tls13"));
        assert!(!log_target_is_visible("tungstenite::protocol"));
        assert!(!log_target_is_visible(
            "tungstenite::protocol::frame::socket"
        ));
        assert!(log_target_is_visible("tungstenite::handshake"));
        assert!(log_target_is_visible("truapi_server::runtime"));
    }

    #[test]
    fn signing_host_exec_accepts_one_slash_command() {
        let cli = Cli::try_parse_from([
            "truapi-host",
            "signing-host",
            "--auto-accept",
            "exec",
            "/help",
        ])
        .expect("exec slash command should parse");
        let Command::SigningHost(args) = cli.command else {
            panic!("expected signing-host command");
        };
        let Some(SigningHostAction::Exec { command }) = args.action else {
            panic!("expected exec action");
        };
        assert_eq!(command, "/help");
        assert_eq!(args.frame_listen, None);
    }

    #[test]
    fn frame_listen_explicitly_selects_tcp_websockets() {
        let cli = Cli::try_parse_from([
            "truapi-host",
            "pairing-host",
            "--frame-listen",
            "127.0.0.1:0",
        ])
        .expect("explicit TCP frame listener should parse");
        let Command::PairingHost(args) = cli.command else {
            panic!("expected pairing-host command");
        };

        assert_eq!(
            args.frame_listen,
            Some("127.0.0.1:0".parse().expect("valid socket address"))
        );
    }

    #[test]
    fn signing_host_rejects_script_and_exec_together() {
        let cli = Cli::try_parse_from([
            "truapi-host",
            "signing-host",
            "--script",
            "smoke.ts",
            "exec",
            "/help",
        ])
        .expect("clap should parse parent options before exec");
        let Command::SigningHost(args) = cli.command else {
            panic!("expected signing-host command");
        };
        assert!(
            validate_signing_args(&args)
                .unwrap_err()
                .to_string()
                .contains("--script cannot be combined")
        );
    }

    #[test]
    fn signing_host_serve_needs_no_tty_and_refuses_one_shot_modes() {
        let cli = Cli::try_parse_from([
            "truapi-host",
            "signing-host",
            "--serve",
            "--frame-listen",
            "127.0.0.1:9955",
            "--auto-accept",
        ])
        .expect("serve should parse");
        let Command::SigningHost(args) = cli.command else {
            panic!("expected signing-host command");
        };
        assert!(args.serve);
        assert!(validate_signing_args(&args).is_ok());

        let with_script = Cli::try_parse_from([
            "truapi-host",
            "signing-host",
            "--serve",
            "--script",
            "smoke.ts",
        ])
        .expect("serve with a script should parse");
        let Command::SigningHost(args) = with_script.command else {
            panic!("expected signing-host command");
        };
        assert!(
            validate_signing_args(&args)
                .unwrap_err()
                .to_string()
                .contains("--serve cannot be combined with --script")
        );

        let with_exec =
            Cli::try_parse_from(["truapi-host", "signing-host", "--serve", "exec", "/help"])
                .expect("serve with exec should parse");
        let Command::SigningHost(args) = with_exec.command else {
            panic!("expected signing-host command");
        };
        assert!(
            validate_signing_args(&args)
                .unwrap_err()
                .to_string()
                .contains("--serve cannot be combined with the exec subcommand")
        );
    }

    #[test]
    fn serve_ready_names_the_endpoint_and_the_approval_policy() {
        let prompting = terminal_ui::SystemEvent::ServeReady {
            url: "ws://127.0.0.1:9955".to_string(),
            auto_accept: false,
        }
        .human();
        assert!(prompting.contains("ws://127.0.0.1:9955"));
        assert!(prompting.contains("--auto-accept"));

        let accepting = terminal_ui::SystemEvent::ServeReady {
            url: "ws://127.0.0.1:9955".to_string(),
            auto_accept: true,
        }
        .human();
        assert!(accepting.contains("approved automatically"));
    }

    #[test]
    fn signing_host_accepts_a_startup_session() {
        let cli = Cli::try_parse_from([
            "truapi-host",
            "signing-host",
            "--session",
            "alice",
            "exec",
            "/session",
        ])
        .expect("startup session should parse");
        let Command::SigningHost(args) = cli.command else {
            panic!("expected signing-host command");
        };

        assert_eq!(args.session.as_deref(), Some("alice"));
        assert!(validate_signing_args(&args).is_ok());
    }

    #[test]
    fn bare_script_selection_reuses_the_last_existing_script() -> Result<()> {
        let temporary = tempfile::tempdir()?;
        let mut last_script = None;

        let first = select_script_to_edit(temporary.path(), &mut last_script)?;
        let second = select_script_to_edit(temporary.path(), &mut last_script)?;
        assert_eq!(second, first);

        std::fs::remove_file(&first)?;
        let replacement = select_script_to_edit(temporary.path(), &mut last_script)?;
        assert_ne!(replacement, first);
        assert!(replacement.is_file());
        Ok(())
    }

    #[test]
    fn explicit_script_becomes_the_next_bare_script_selection() -> Result<()> {
        let temporary = tempfile::tempdir()?;
        let scripts = temporary.path().join("scripts");
        std::fs::create_dir_all(&scripts)?;
        let mut last_script = Some(script_runner::create_scratch_script(&scripts)?);
        let explicit = temporary.path().join("product-script.ts");
        std::fs::write(&explicit, "console.log('product');")?;

        let remembered =
            remember_script(Some(temporary.path()), &mut last_script, explicit.clone())?;
        let selected = select_script_to_edit(&scripts, &mut last_script)?;

        assert_eq!(remembered, explicit);
        assert_eq!(selected, explicit);
        assert_eq!(
            sessions::session_last_script(temporary.path())?.as_deref(),
            Some(explicit.as_path())
        );
        Ok(())
    }

    #[test]
    fn signing_host_rejects_managed_session_with_mnemonic() {
        let cli = Cli::try_parse_from([
            "truapi-host",
            "signing-host",
            "--mnemonic",
            "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
            "--session",
            "alice",
            "exec",
            "/session",
        ])
        .expect("clap should parse conflicting signer options");
        let Command::SigningHost(args) = cli.command else {
            panic!("expected signing-host command");
        };

        assert!(
            validate_signing_args(&args)
                .unwrap_err()
                .to_string()
                .contains("--session cannot be used")
        );
    }

    #[test]
    fn paired_device_management_rejects_an_ephemeral_mnemonic_session() {
        let cli = Cli::try_parse_from([
            "truapi-host",
            "signing-host",
            "--mnemonic",
            "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
            "exec",
            "/devices",
        ])
        .expect("clap should parse the command before lifecycle validation");
        let Command::SigningHost(args) = cli.command else {
            panic!("expected signing-host command");
        };

        assert_eq!(
            validate_signing_args(&args).unwrap_err().to_string(),
            "paired-device management is unavailable when launched with --mnemonic"
        );
    }
}
