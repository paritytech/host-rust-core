//! Ask a real runtime whether it accepts the six `AsCoinage` origins.
//!
//! `coinage_chain_agreement` confirms the six variants *exist* at the indices the
//! layer assumes. That is not the same as the runtime accepting one: the encoding
//! of five of them was read off the pallet source and has never been through a
//! node. This driver closes that gap the cheap way — it assembles each variant into
//! a real extrinsic and **dry-runs** it. Nothing is broadcast, no coin is owned, no
//! value moves.
//!
//! # Reading the answers
//!
//! A dry-run rejection is not a failure here; the *kind* of rejection is the whole
//! result:
//!
//! - **`Invalid::Custom(n)`** — the best outcome available without owning a coin.
//!   The runtime parsed our extra, reached the pallet's own checks, and refused for
//!   a reason of its own ("no such coin", "no such token"). The encoding is right.
//! - **`Invalid::BadProof`** — parsed, and the proof inside was rejected. Expected
//!   for every variant carrying a placeholder proof, and again evidence the shape
//!   was understood.
//! - **`Invalid::Call` / a decode failure** — the runtime could not make sense of
//!   the transaction at all. That is an encoding bug, and the one answer worth
//!   acting on.
//! - **Accepted** — only reachable for a variant whose origin really exists, which
//!   means the wallet this ran with owns a coin.
//!
//! ```text
//! cargo run --example coinage_live_validation
//! cargo run --example coinage_live_validation -- --url wss://host
//! COINAGE_ENTROPY=0x… cargo run --example coinage_live_validation
//! ```
//!
//! With `COINAGE_ENTROPY` the coin-origin variant is signed by a key derived the
//! way the layer derives one, so a wallet that holds a coin at index 0 of its main
//! purse can turn this into an acceptance rather than a `Custom`. Without it, a
//! throwaway key is used and the coin is expected to be missing.
//!
//! # What this still does not cover
//!
//! Mortality expiry and `post_dispatch` failure-lock behaviour need a transaction
//! that actually lands, and therefore a funded wallet. They are the reason E1
//! exists at all, and they remain the next thing to do against a testnet.

use schnorrkel::{ExpansionMode, Keypair, MiniSecretKey};

use truapi_server::coinage::call::{
    CoinOutput, RawEncoded, SplitInto, UnloadRecyclerIntoCoinsArgs,
};
use truapi_server::coinage::extension::{AsCoinageInfo, FreeTokenRing};
use truapi_server::coinage::extrinsic::{
    CoinageCall, build_call, build_coin_origin_extrinsic, build_unsigned_extrinsic,
};
use truapi_server::coinage::submit::{dry_run, fetch_mortal_chain_state};
use truapi_server::host_logic::coinage::chain_constants::next_people_paseo;
use truapi_server::host_logic::coinage::derivation;
use truapi_server::host_logic::coinage::types::{
    CoinAccountId, CoinIndex, DenominationExponent, PurseId, RevisionIndex, RingIndex, RingLocation,
};
use truapi_server::statement_allowance::extension::Metadata;
use truapi_server::statement_allowance::fetch_metadata;
use truapi_server::statement_allowance::rpc::RpcClient;

/// People chain on the CLI host's default network.
const DEFAULT_URL: &str = "wss://paseo-people-next-system-rpc.polkadot.io";

/// Length of a single-context ring-VRF signature, which both the token proof and
/// each alias proof are.
const RING_VRF_PROOF_LEN: usize = 785;

/// What a dry-run told us about one variant.
enum Verdict {
    /// The runtime would accept it.
    Accepted,
    /// Parsed, then refused by the pallet's own checks. The encoding is right.
    Reached(String),
    /// Refused before the pallet: the transaction was not understood.
    Malformed(String),
}

impl Verdict {
    /// Classify a dry-run result.
    ///
    /// The distinction that matters is whether the runtime got far enough to
    /// disagree with us about *state* rather than about *bytes*.
    fn of(result: Result<(), String>) -> Self {
        match result {
            Ok(()) => Self::Accepted,
            Err(reason) => {
                let reached = reason.contains("Custom")
                    || reason.contains("BadProof")
                    || reason.contains("Payment")
                    || reason.contains("Stale")
                    || reason.contains("Future");
                if reached {
                    Self::Reached(reason)
                } else {
                    Self::Malformed(reason)
                }
            }
        }
    }

    fn render(&self, label: &str) -> bool {
        match self {
            Self::Accepted => {
                println!("  ok      {label}: accepted — the origin exists and the proofs hold");
                true
            }
            Self::Reached(reason) => {
                println!("  parsed  {label}: {reason}");
                true
            }
            Self::Malformed(reason) => {
                println!("  BAD     {label}: {reason}");
                false
            }
        }
    }
}

/// A placeholder proof of the right length.
///
/// Length matters and content does not: a proof of the wrong length changes how
/// the extension decodes, which would turn an encoding question into a decoding
/// accident.
fn placeholder_proof() -> RawEncoded {
    RawEncoded(vec![0xAB; RING_VRF_PROOF_LEN])
}

/// The unload call every token-bearing variant is tried against.
fn unload_call(metadata: &Metadata) -> Result<Vec<u8>, Box<dyn std::error::Error>> {
    let constants = next_people_paseo();
    let exponent = DenominationExponent::new(4).ok_or("4 is a denomination")?;
    let outputs = [CoinOutput {
        exponent,
        account: CoinAccountId([0x11; 32]),
    }];
    let args = UnloadRecyclerIntoCoinsArgs::new(
        vec![[0x22; 32]],
        exponent,
        RingLocation::new(RingIndex(0), RevisionIndex(0)),
        &outputs,
        0,
        &constants,
    )?;

    Ok(build_call(
        metadata,
        CoinageCall::UnloadRecyclerIntoCoins,
        &args,
    )?)
}

/// The six variants, each with the call it makes sense against.
fn variants() -> Vec<(&'static str, AsCoinageInfo)> {
    let alias_proofs = vec![placeholder_proof()];

    vec![
        (
            "AsUnloadTokenPeople",
            AsCoinageInfo::FreeUnloadToken {
                ring: FreeTokenRing::People,
                proof: placeholder_proof(),
                period: 0,
                counter: 0,
                alias_proofs: alias_proofs.clone(),
            },
        ),
        (
            "AsUnloadTokenLitePeople",
            AsCoinageInfo::FreeUnloadToken {
                ring: FreeTokenRing::LitePeople,
                proof: placeholder_proof(),
                period: 0,
                counter: 0,
                alias_proofs: alias_proofs.clone(),
            },
        ),
        (
            "AsUnloadTokenPaid",
            AsCoinageInfo::PaidUnloadToken {
                proof: placeholder_proof(),
                period: 0,
                ring: RingLocation::new(RingIndex(0), RevisionIndex(0)),
                alias_proofs: alias_proofs.clone(),
            },
        ),
        (
            "AsUnloadTokenFromOutput",
            AsCoinageInfo::UnloadTokenFromOutput {
                fee_recycler_value: DenominationExponent::new(4).expect("4 is a denomination"),
                fee_recycler_ring: RingLocation::new(RingIndex(0), RevisionIndex(0)),
                retry_counter: 0,
                alias_proofs,
            },
        ),
        (
            "InfallibleUnpaidSigned",
            AsCoinageInfo::InfallibleUnpaidSigned { nonce: 0 },
        ),
    ]
}

/// The keypair the coin-origin variant signs with.
///
/// With entropy, the layer's own derivation for the main purse's first coin, so a
/// wallet that holds one can produce an acceptance. Without, a throwaway key whose
/// account the chain has certainly never seen.
fn coin_signer(entropy: Option<&[u8]>) -> Result<(Keypair, bool), Box<dyn std::error::Error>> {
    match entropy {
        Some(entropy) => Ok((
            derivation::coin_keypair(entropy, PurseId::MAIN, CoinIndex(0))?,
            true,
        )),
        None => Ok((
            MiniSecretKey::from_bytes(&[0x5c; 32])
                .map_err(|error| format!("throwaway key: {error}"))?
                .expand_to_keypair(ExpansionMode::Ed25519),
            false,
        )),
    }
}

fn arg(name: &str) -> Option<String> {
    let mut args = std::env::args().skip(1);
    while let Some(candidate) = args.next() {
        if candidate == name {
            return args.next();
        }
    }
    None
}

fn entropy_from_environment() -> Option<Vec<u8>> {
    let raw = std::env::var("COINAGE_ENTROPY").ok()?;
    hex::decode(raw.trim().strip_prefix("0x").unwrap_or(raw.trim())).ok()
}

/// Dry-run one assembled extrinsic and reduce the outcome to a string.
async fn ask(rpc: &RpcClient, extrinsic: &[u8]) -> Result<(), String> {
    dry_run(rpc, extrinsic)
        .await
        .map_err(|error| error.to_string())
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let url = arg("--url").unwrap_or_else(|| DEFAULT_URL.to_string());
    let entropy = entropy_from_environment();

    println!("coinage live validation");
    println!("  url {url}");
    println!(
        "  entropy {}",
        if entropy.is_some() {
            "from COINAGE_ENTROPY"
        } else {
            "absent — the coin origin will be a throwaway key"
        }
    );

    let rpc = RpcClient::connect(&url).await?;
    let metadata = fetch_metadata(&rpc).await?;
    let (state, anchor) = fetch_mortal_chain_state(&rpc).await?;
    println!(
        "  era anchored at #{} for {} blocks\n",
        anchor.number, anchor.period
    );

    let mut understood = 0usize;
    let mut malformed = Vec::new();

    // -- the coin origin ---------------------------------------------------
    println!("origins");
    let (keypair, derived) = coin_signer(entropy.as_deref())?;
    let transfer = build_call(
        &metadata,
        CoinageCall::Transfer,
        &truapi_server::coinage::call::TransferArgs::new(CoinAccountId([0x33; 32])),
    )?;
    let coin_origin = build_coin_origin_extrinsic(&metadata, &state, &transfer, &keypair)?;
    let label = if derived {
        "AsCoin (derived key)"
    } else {
        "AsCoin (throwaway key)"
    };
    if Verdict::of(ask(&rpc, &coin_origin).await).render(label) {
        understood += 1;
    } else {
        malformed.push(label.to_string());
    }

    // -- the five unsigned origins ----------------------------------------
    let call = unload_call(&metadata)?;
    for (label, info) in variants() {
        let extra = info.encode_extra(&metadata)?;
        let extrinsic = build_unsigned_extrinsic(&metadata, &state, &call, &extra)?;
        if Verdict::of(ask(&rpc, &extrinsic).await).render(label) {
            understood += 1;
        } else {
            malformed.push(label.to_string());
        }
    }

    // -- a shape check that needs no chain --------------------------------
    println!("\nshapes");
    let split = SplitInto::from_outputs(
        &[CoinOutput {
            exponent: DenominationExponent::new(3).expect("3 is a denomination"),
            account: CoinAccountId([1; 32]),
        }],
        &next_people_paseo(),
    )?;
    println!(
        "  ok      split_into groups by denomination: {} group(s)",
        split.0.len()
    );

    println!("\n{understood}/6 origins reached the runtime's own checks");
    if malformed.is_empty() {
        println!("no encoding was rejected as unintelligible");
        Ok(())
    } else {
        println!("unintelligible to the runtime: {}", malformed.join(", "));
        Err("at least one AsCoinage encoding was not understood".into())
    }
}
