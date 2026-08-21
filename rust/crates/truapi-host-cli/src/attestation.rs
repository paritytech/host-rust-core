//! Lite-username attestation against the identity backend.
//!
//! Fetches the backend verifier. Builds the client proofs
//! (`truapi_server::host_logic::attestation`), including the dotNS gateway
//! reservation signature timestamped with Asset Hub chain time. POSTs them to
//! `/usernames`. Polls the dotNS contracts on Asset Hub until the lite username
//! lands.
//!
//! Registers the signing host's RFC-0022 `uid.dot` identity account. The paired
//! host can then resolve its username via `get_user_id`.

use std::time::Duration;

use anyhow::{Context, Result, bail};
use base64::Engine as _;
use base64::engine::general_purpose::STANDARD as BASE64;
use bip39::Mnemonic;
use serde_json::{Value, json};
use sha2::{Digest as _, Sha256};
use std::sync::Mutex;
use tracing::{debug, warn};
use truapi_server::host_logic::attestation::build_lite_registration;
use truapi_server::host_logic::dotns_gateway::{
    MAX_BASE_LABEL_LEN, MIN_PERSON_LABEL_LEN, is_registrable_full_label,
};
use truapi_server::host_logic::product_account::{
    SR25519_SIGNING_CONTEXT, derive_identity_keypair, derive_root_keypair_from_entropy,
    product_public_key_to_address,
};

use crate::dotns_read::AssetHubReader;

/// Env var carrying an optional bearer token for the identity backend.
/// Set it to reuse a token minted elsewhere. Unset, the CLI runs the sr25519
/// auth handshake itself ([`backend_token`]).
pub const IDENTITY_BACKEND_TOKEN_ENV: &str = "HOST_CLI_IDENTITY_BACKEND_TOKEN";

/// Access tokens for the username routes, minted once per backend base and
/// process. Keyed by base so two backends in one process never share a token.
static BACKEND_TOKENS: Mutex<Vec<(String, &'static str)>> = Mutex::new(Vec::new());

/// Bearer token for the identity backend's username routes.
///
/// The explicit env token wins. Otherwise the CLI completes the backend's
/// `challenges` → `token` sr25519 handshake with a throwaway keypair. The JWT
/// subject only identifies the calling app instance. The username claim carries
/// its own candidate account. A fresh subject each run keeps repeat
/// registrations clear of the per-subject device gate and rate limit.
async fn backend_token(client: &reqwest::Client, backend_base: &str) -> Result<&'static str> {
    if let Ok(token) = std::env::var(IDENTITY_BACKEND_TOKEN_ENV)
        && !token.trim().is_empty()
    {
        return Ok(Box::leak(token.trim().to_string().into_boxed_str()));
    }
    let cached = BACKEND_TOKENS
        .lock()
        .expect("backend token cache mutex poisoned")
        .iter()
        .find(|(base, _)| base == backend_base)
        .map(|(_, token)| *token);
    if let Some(token) = cached {
        return Ok(token);
    }
    let token: &'static str = Box::leak(
        mint_backend_token(client, backend_base)
            .await?
            .into_boxed_str(),
    );
    BACKEND_TOKENS
        .lock()
        .expect("backend token cache mutex poisoned")
        .push((backend_base.to_string(), token));
    Ok(token)
}

/// Runs the backend's auth handshake and returns its access JWT.
async fn mint_backend_token(client: &reqwest::Client, backend_base: &str) -> Result<String> {
    let url = format!("{backend_base}/auth/challenges");
    let body: Value = client
        .post(&url)
        .json(&json!({}))
        .send()
        .await
        .with_context(|| format!("POST {url}"))?
        .error_for_status()?
        .json()
        .await
        .context("decoding challenge response")?;
    let challenge = body
        .get("challenge")
        .and_then(Value::as_str)
        .context("challenge response missing 'challenge' field")?
        .to_string();
    let challenge_bytes = BASE64
        .decode(&challenge)
        .context("challenge is not valid base64")?;

    let entropy = Mnemonic::generate(12)
        .context("generate throwaway auth mnemonic")?
        .to_entropy();
    let keypair = derive_root_keypair_from_entropy(&entropy)
        .map_err(|err| anyhow::anyhow!("auth keypair derivation failed: {err}"))?;
    let client_id = keypair.public.to_bytes();

    // The proof signs SHA256(challenge || clientId || SHA256(body)). It must
    // cover the exact bytes the request carries, so the body is serialized once.
    let payload = b"{}";
    let mut hasher = Sha256::new();
    hasher.update(&challenge_bytes);
    hasher.update(client_id);
    hasher.update(Sha256::digest(payload));
    let message: [u8; 32] = hasher.finalize().into();
    let proof = keypair
        .secret
        .sign_simple(SR25519_SIGNING_CONTEXT, &message, &keypair.public)
        .to_bytes();

    let url = format!("{backend_base}/auth/token");
    let response = client
        .post(&url)
        .header("Auth-ClientId", BASE64.encode(client_id))
        .header("Auth-ClientProof", BASE64.encode(proof))
        .header("Auth-Challenge", &challenge)
        .header(reqwest::header::CONTENT_TYPE, "application/json")
        .body(payload.as_slice())
        .send()
        .await
        .with_context(|| format!("POST {url}"))?;
    let status = response.status();
    let body = response.text().await.unwrap_or_default();
    if !status.is_success() {
        bail!("identity backend auth handshake failed ({status}): {body}");
    }
    let body: Value = serde_json::from_str(&body).context("decoding token response")?;
    let token = body
        .get("token")
        .and_then(Value::as_str)
        .context("token response missing 'token' field")?;
    debug!("minted identity backend access token");
    Ok(token.to_string())
}

/// Attaches the identity backend bearer token to `request`.
async fn with_backend_auth(
    client: &reqwest::Client,
    backend_base: &str,
    request: reqwest::RequestBuilder,
) -> Result<reqwest::RequestBuilder> {
    Ok(request.bearer_auth(backend_token(client, backend_base).await?))
}

/// Inputs for one attestation run.
pub struct AttestConfig {
    /// Identity backend base URL including `/api/v1`.
    pub backend_base: String,
    /// Asset Hub WebSocket URL for the reservation timestamp and the dotNS
    /// username poll.
    pub asset_hub_ws: String,
    /// BIP-39 entropy of the signing host's root account.
    pub entropy: Vec<u8>,
    /// Requested lite username base (6+ lowercase letters, no digits).
    pub username_base: String,
    /// Optional base name to queue on dotNS for a later full-person claim.
    pub reserved_username: Option<String>,
}

/// Check whether a lite username base is available through the identity
/// backend. The username must be the base form without the digit suffix.
pub async fn lite_username_available(backend_base: &str, username_base: &str) -> Result<bool> {
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(30))
        .build()?;
    let url = format!("{backend_base}/usernames/available");
    let body = json!({ "usernames": [username_base] });
    let response = with_backend_auth(&client, backend_base, client.post(&url).json(&body))
        .await?
        .send()
        .await
        .with_context(|| format!("POST {url}"))?;
    let status = response.status();
    if !status.is_success() {
        let text = response.text().await.unwrap_or_default();
        bail!("username availability check failed for {username_base} ({status}): {text}");
    }
    let body: Value = response
        .json()
        .await
        .context("decoding availability response")?;
    Ok(availability_status(&body, username_base) == Some("AVAILABLE"))
}

/// Reads one base's status out of the availability response, a flat
/// `{base: "AVAILABLE" | …}` map.
fn availability_status<'a>(body: &'a Value, username_base: &str) -> Option<&'a str> {
    body.get(username_base).and_then(Value::as_str)
}

/// Registers (or confirms) the signing host's lite username. Waits until the
/// dotNS contracts on Asset Hub record it. Returns the lite username assigned on
/// chain, including its discriminator.
pub async fn attest(config: &AttestConfig) -> Result<String> {
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(30))
        .build()?;

    let mut reader = AssetHubReader::connect(&config.asset_hub_ws).await?;
    // Timestamping the reservation signature with Asset Hub chain time. The
    // gateway rejects values ahead of the chain.
    let signed_at = reader
        .timestamp_secs()
        .await
        .context("read Asset Hub Timestamp.Now")?;

    // A reserved base name that is already registered can never be claimed,
    // yet the reservation would hold that stem's queue for the whole
    // reservation window; neither the backend nor the gateway checks it. Ask
    // the registrar first.
    if let Some(reserved) = config.reserved_username.as_deref() {
        if !is_registrable_full_label(reserved) {
            bail!(
                "reserved username {reserved:?} is not a reservable base label (lowercase ASCII \
                 letters only, {MIN_PERSON_LABEL_LEN} to {MAX_BASE_LABEL_LEN} bytes); the \
                 gateway would reject the whole attestation"
            );
        }
        if !reader.label_available(reserved).await? {
            bail!(
                "reserved username {reserved:?} is already registered on dotNS; a reservation \
                 for it could never be claimed and would lock the stem's reservation queue"
            );
        }
    }

    let verifier = fetch_verifier(&client, &config.backend_base).await?;
    let registration = build_lite_registration(
        &config.entropy,
        verifier,
        &config.username_base,
        config.reserved_username.as_deref(),
        signed_at,
    )
    .map_err(|reason| anyhow::anyhow!("failed to build registration params: {reason}"))?;
    debug!(
        candidate = %registration.candidate_account_id,
        "attesting lite username '{}'",
        config.username_base
    );

    submit_registration(
        &client,
        &config.backend_base,
        &config.username_base,
        config.reserved_username.as_deref(),
        signed_at,
        &registration,
    )
    .await?;

    let identity = wait_for_dotns_username(&mut reader, &registration.candidate_public_key).await?;
    debug!("lite username registered and confirmed on-chain");
    identity
        .lite_username
        .context("registered dotNS identity has no lite username")
}

/// Resolves the on-chain lite username for an already-attested signer: the
/// discriminated `name.NN` the dotNS contracts hold for its identity account,
/// whatever base the account record asked for.
pub async fn registered_lite_username(asset_hub_ws: &str, entropy: &[u8]) -> Result<String> {
    let identity = derive_identity_keypair(entropy)
        .map_err(|err| anyhow::anyhow!("uid.dot identity derivation failed: {err}"))?;
    let mut reader = AssetHubReader::connect(asset_hub_ws).await?;
    reader
        .dotns_identity(&identity.public.to_bytes())
        .await?
        .lite_username
        .context("attested signer has no dotNS lite username")
}

/// Probes the dotNS contracts for the bare root and canonical RFC-0022 `uid.dot`
/// identity account. Prints any recorded usernames. Used to confirm a
/// pre-onboarded account.
pub async fn check_identity(asset_hub_ws: &str, entropy: &[u8]) -> Result<()> {
    let root = derive_root_keypair_from_entropy(entropy)
        .map_err(|err| anyhow::anyhow!("invalid entropy: {err}"))?;
    let identity = derive_identity_keypair(entropy)
        .map_err(|err| anyhow::anyhow!("uid.dot identity derivation failed: {err}"))?;
    let mut reader = AssetHubReader::connect(asset_hub_ws).await?;

    for (label, public) in [
        ("<root>", root.public.to_bytes()),
        (
            "//product//uid.dot/index_bytes(0)",
            identity.public.to_bytes(),
        ),
    ] {
        let address = product_public_key_to_address(public);
        match reader.dotns_identity(&public).await {
            Ok(identity) => match identity.full_username.or(identity.lite_username) {
                Some(username) => {
                    println!("IDENTITY_FOUND path={label} account={address} username={username}")
                }
                None => println!("IDENTITY_NONE path={label} account={address}"),
            },
            Err(err) => println!("IDENTITY_ERROR path={label} account={address} error={err:#}"),
        }
    }
    Ok(())
}

async fn fetch_verifier(client: &reqwest::Client, backend_base: &str) -> Result<[u8; 32]> {
    let url = format!("{backend_base}/attester");
    let body: Value = client
        .get(&url)
        .send()
        .await
        .with_context(|| format!("GET {url}"))?
        .error_for_status()?
        .json()
        .await
        .context("decoding attester response")?;
    let hex_value = body
        .get("attester")
        .and_then(Value::as_str)
        .context("attester response missing 'attester' field")?;
    let bytes = hex::decode(hex_value.strip_prefix("0x").unwrap_or(hex_value))
        .context("attester is not valid hex")?;
    <[u8; 32]>::try_from(bytes)
        .map_err(|bytes| anyhow::anyhow!("attester must be 32 bytes, got {}", bytes.len()))
}

async fn submit_registration(
    client: &reqwest::Client,
    backend_base: &str,
    username_base: &str,
    reserved_username: Option<&str>,
    signed_at: u64,
    reg: &truapi_server::host_logic::attestation::LiteRegistration,
) -> Result<()> {
    let url = format!("{backend_base}/usernames");
    let mut dotns = json!({
        "signature": hex0x(&reg.dotns_signature),
        "signedAt": signed_at,
    });
    if let Some(reserved) = reserved_username {
        dotns["reservedUsername"] = json!(reserved);
    }
    let body = json!({
        "username": username_base,
        "candidateAccountId": reg.candidate_account_id,
        "candidateSignature": hex0x(&reg.candidate_signature),
        "ringVrfKey": hex0x(&reg.ring_vrf_key),
        "proofOfOwnership": hex0x(&reg.proof_of_ownership),
        "identifierKey": hex0x(&reg.identifier_key),
        "consumerRegistrationSignature": hex0x(&reg.consumer_registration_signature),
        "dotns": dotns,
    });
    let response = with_backend_auth(client, backend_base, client.post(&url).json(&body))
        .await?
        .send()
        .await
        .with_context(|| format!("POST {url}"))?;
    let status = response.status();
    if status.is_success() {
        let text = response.text().await.unwrap_or_default();
        debug!(%status, body = %text, "POST /usernames accepted");
        return Ok(());
    }
    let text = response.text().await.unwrap_or_default();
    // Already-registered is a soft success; the on-chain poll confirms it.
    if text.contains("already") || text.contains("AlreadyRegistered") || text.contains("duplicate")
    {
        warn!(%status, body = %text, "username already registered; confirming on-chain");
        return Ok(());
    }
    if text.contains("dotNS gateway is not enabled") {
        bail!(
            "username registration failed ({status}): {text}\n\
             This identity backend does not record usernames on the dotNS gateway, and the \
             host reads usernames only from dotNS on Asset Hub, so no username can be \
             resolved for accounts registered through it. Use a preset whose backend has \
             the gateway enabled (`--network previewnet`), or point \
             HOST_CLI_IDENTITY_BACKEND_BASE at one that does."
        );
    }
    bail!("username registration failed ({status}): {text}");
}

fn hex0x(bytes: &[u8]) -> String {
    format!("0x{}", hex::encode(bytes))
}

async fn wait_for_dotns_username(
    reader: &mut AssetHubReader,
    candidate: &[u8; 32],
) -> Result<truapi_server::host_logic::dotns_gateway::DotnsIdentity> {
    // First-time lite registration is backend-async and can lag the HTTP
    // response. The record is permanent once written. Later runs therefore
    // resolve on the first poll.
    const MAX_ATTEMPTS: usize = 10;
    for attempt in 1..=MAX_ATTEMPTS {
        match reader.dotns_identity(candidate).await {
            Ok(identity) if identity.lite_username.is_some() => {
                crate::terminal_ui::update_activity(
                    "signer",
                    "Setting up signer",
                    Some("dotNS identity ready".to_string()),
                    crate::terminal_ui::ActivityState::Running,
                );
                return Ok(identity);
            }
            Ok(_) => {
                crate::terminal_ui::update_activity(
                    "signer",
                    "Setting up signer",
                    Some(format!(
                        "Waiting for dotNS username · attempt {attempt}/{MAX_ATTEMPTS}"
                    )),
                    crate::terminal_ui::ActivityState::Running,
                );
                debug!("dotNS username poll {attempt}/{MAX_ATTEMPTS}: empty");
            }
            Err(err) => warn!(%err, "dotNS username poll attempt {attempt} failed"),
        }
        if attempt < MAX_ATTEMPTS {
            tokio::time::sleep(Duration::from_secs(4)).await;
        }
    }
    bail!("dotNS username did not appear on Asset Hub after attestation")
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The availability response is a flat `{base: status}` map.
    #[test]
    fn availability_reads_the_flat_status_map() {
        let flat = json!({ "pntest": "EXHAUSTED", "other": "AVAILABLE" });
        assert_eq!(availability_status(&flat, "pntest"), Some("EXHAUSTED"));
        assert_eq!(availability_status(&flat, "other"), Some("AVAILABLE"));
        assert_eq!(availability_status(&flat, "missing"), None);
    }
}
