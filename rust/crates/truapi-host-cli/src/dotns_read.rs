//! Asset Hub dotNS reads over plain RPC (`state_getStorage` / `state_call`).
//!
//! The transport half of username resolution. This module supplies the two RPC
//! primitives. `truapi_server::host_logic::dotns_gateway` walks the contract
//! chain over them. The CLI and the in-core `chainHead_v1` lookup therefore
//! resolve identically.

use anyhow::{Context, Result, bail};
use serde_json::Value;
use subxt_rpcs::client::{RpcClient, rpc_params};
use truapi_platform::async_trait;
use truapi_server::host_logic::dotns_gateway::{
    DotnsIdentity, DotnsTransport, VIEW_CALL_ORIGIN, account_alias_key, classify_labels,
    decode_revive_call_output, discover_pop_controller, encode_revive_call, label_available,
    resolve_labels, timestamp_now_key,
};

/// Env var overriding the `DotnsPopController` H160 (hex), skipping on-chain
/// discovery.
///
/// Discovery reads `DotnsGateway.DispatcherAddress` and asks the dispatcher
/// for its `TARGET()`; the override is for networks where that fails. The
/// controller is `0xCC932348606cc1f3318cADeC5A5Cd2CA447f8a4b` on paseo-next-v2
/// and previewnet; `DEPLOYMENTS.md` in paritytech/dotns is the authority per
/// network.
pub const DOTNS_POP_CONTROLLER_ENV: &str = "HOST_CLI_DOTNS_POP_CONTROLLER";

/// One Asset Hub RPC connection for a batch of dotNS reads.
pub struct AssetHubReader {
    rpc: RpcClient,
}

impl AssetHubReader {
    /// Connects to the Asset Hub WebSocket endpoint.
    pub async fn connect(asset_hub_ws: &str) -> Result<Self> {
        let rpc = RpcClient::from_insecure_url(asset_hub_ws)
            .await
            .with_context(|| format!("connect {asset_hub_ws}"))?;
        Ok(Self { rpc })
    }

    /// Asset Hub chain time in Unix seconds. `Timestamp.Now` itself is
    /// milliseconds.
    pub async fn timestamp_secs(&self) -> Result<u64> {
        let value = self
            .raw_storage(&timestamp_now_key())
            .await?
            .context("Timestamp.Now is unset")?;
        let millis: [u8; 8] = value
            .as_slice()
            .try_into()
            .map_err(|_| anyhow::anyhow!("Timestamp.Now is not a u64"))?;
        Ok(u64::from_le_bytes(millis) / 1000)
    }

    /// Alias `account` registered with, per `DotnsGateway.AccountAlias`.
    pub async fn account_alias(&self, account: &[u8; 32]) -> Result<Option<[u8; 32]>> {
        let value = self.raw_storage(&account_alias_key(account)).await?;
        Ok(value.and_then(|bytes| bytes.try_into().ok()))
    }

    /// Usernames of `account` as recorded by the dotNS contracts.
    pub async fn dotns_identity(&mut self, account: &[u8; 32]) -> Result<DotnsIdentity> {
        let controller = self.pop_controller().await?;
        let labels = resolve_labels(self, &controller, account)
            .await
            .map_err(anyhow::Error::msg)?;
        Ok(classify_labels(labels))
    }

    /// Whether the registrar would still mint `label` under the network TLD.
    /// `false` once the name is registered, whichever flow minted it.
    pub async fn label_available(&mut self, label: &str) -> Result<bool> {
        let controller = self.pop_controller().await?;
        label_available(self, &controller, label)
            .await
            .map_err(anyhow::Error::msg)
    }

    /// `DotnsPopController` address. The env override wins, otherwise on-chain
    /// discovery through the dispatcher's `TARGET()` getter.
    async fn pop_controller(&mut self) -> Result<[u8; 20]> {
        if let Ok(value) = std::env::var(DOTNS_POP_CONTROLLER_ENV) {
            let trimmed = value.trim();
            if !trimmed.is_empty() {
                let bytes = hex::decode(trimmed.strip_prefix("0x").unwrap_or(trimmed))
                    .with_context(|| format!("{DOTNS_POP_CONTROLLER_ENV} is not valid hex"))?;
                return bytes.try_into().map_err(|bytes: Vec<u8>| {
                    anyhow::anyhow!(
                        "{DOTNS_POP_CONTROLLER_ENV} must be 20 bytes, got {}",
                        bytes.len()
                    )
                });
            }
        }
        discover_pop_controller(self)
            .await
            .map_err(anyhow::Error::msg)?
            .with_context(|| {
                format!(
                    "dotNS gateway has no reachable controller; set \
                     {DOTNS_POP_CONTROLLER_ENV} to the DotnsPopController H160"
                )
            })
    }

    /// Dry-runs a contract view via the `ReviveApi_call` runtime API and returns
    /// its data.
    ///
    /// Views originate from the synthetic always-mapped account. They work
    /// regardless of the queried account's revive mapping.
    async fn raw_view(&self, dest: &[u8; 20], input: Vec<u8>) -> Result<Vec<u8>> {
        let args = encode_revive_call(&VIEW_CALL_ORIGIN, dest, &input);
        let output: Value = self
            .rpc
            .request(
                "state_call",
                rpc_params!["ReviveApi_call", format!("0x{}", hex::encode(args))],
            )
            .await
            .context("rpc state_call ReviveApi_call")?;
        let Some(output) = output.as_str() else {
            bail!("state_call returned a non-string response");
        };
        let bytes = hex::decode(output.strip_prefix("0x").unwrap_or(output))
            .context("state_call output is not valid hex")?;
        Ok(decode_revive_call_output(&bytes)?)
    }

    /// One `state_getStorage` read at the best block.
    async fn raw_storage(&self, key: &[u8]) -> Result<Option<Vec<u8>>> {
        let value: Value = self
            .rpc
            .request(
                "state_getStorage",
                rpc_params![format!("0x{}", hex::encode(key))],
            )
            .await
            .context("rpc state_getStorage")?;
        value
            .as_str()
            .map(|hex_value| {
                hex::decode(hex_value.strip_prefix("0x").unwrap_or(hex_value))
                    .context("storage value is not valid hex")
            })
            .transpose()
    }
}

#[async_trait]
impl DotnsTransport for AssetHubReader {
    async fn storage(&mut self, key: Vec<u8>) -> Result<Option<Vec<u8>>, String> {
        self.raw_storage(&key)
            .await
            .map_err(|err| format!("{err:#}"))
    }

    async fn view(&mut self, dest: &[u8; 20], input: Vec<u8>) -> Result<Vec<u8>, String> {
        self.raw_view(dest, input)
            .await
            .map_err(|err| format!("{err:#}"))
    }
}
