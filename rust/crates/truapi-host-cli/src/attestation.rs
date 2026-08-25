//! Lite-username attestation against the People-chain identity backend.
//!
//! Ports signing-bot `attestation.ts`: fetch the backend verifier, build the
//! client proofs (`truapi_server::host_logic::attestation`), POST them to
//! `/usernames`, then poll People-chain `Resources.Consumers` until the record
//! lands. Registers the signing host's RFC-0022 `uid.dot` identity account so
//! the paired host can resolve its username via `get_user_id`.

use std::time::Duration;

use anyhow::{Context, Result, bail};
use base64::Engine as _;
use serde_json::{Value, json};
use sha2::{Digest as _, Sha256};
use subxt_rpcs::client::{RpcClient, rpc_params};
use tracing::{debug, warn};
use truapi_server::host_logic::attestation::build_lite_registration;
use truapi_server::host_logic::identity::{
    decode_people_identity, resources_consumers_storage_key,
};
use truapi_server::host_logic::product_account::{
    derive_identity_keypair, derive_root_keypair_from_entropy, product_public_key_to_address,
};

use crate::network::{IdentityBackendAuth, NetworkConfig};

/// Inputs for one attestation run.
pub struct AttestConfig {
    /// Identity backend base URL including `/api/v1`.
    pub backend_base: String,
    /// Authentication the configured identity backend requires.
    pub backend_auth: IdentityBackendAuth,
    /// People-chain WebSocket URL for the `Resources.Consumers` poll.
    pub people_ws: String,
    /// BIP-39 entropy of the signing host's root account.
    pub entropy: Vec<u8>,
    /// Requested lite username base (6+ lowercase letters, no digits).
    pub username_base: String,
}

/// Check whether a lite username base is available through the identity
/// backend. The username must be the base form without the digit suffix.
pub async fn lite_username_available(
    network: NetworkConfig,
    entropy: &[u8],
    username_base: &str,
) -> Result<bool> {
    let backend = IdentityBackendClient::connect(
        network.identity_backend_base,
        network.identity_backend_auth,
        entropy,
    )
    .await?;
    let url = backend.availability_url();
    let body = json!({ "usernames": [username_base] });
    let response = backend
        .request(reqwest::Method::POST, &url)
        .json(&body)
        .send()
        .await
        .with_context(|| format!("POST {url}"))?
        .error_for_status()
        .with_context(|| format!("username availability check failed for {username_base}"))?;
    let body: Value = response
        .json()
        .await
        .context("decoding availability response")?;
    let legacy_status = body
        .get(username_base)
        .and_then(Value::as_str)
        .is_some_and(|status| status == "AVAILABLE");
    let current_status = body
        .get("value")
        .and_then(|value| value.get(username_base))
        .and_then(|value| value.get("status"))
        .and_then(Value::as_str)
        .is_some_and(|status| status == "AVAILABLE");
    Ok(legacy_status || current_status)
}

/// Register (or confirm) the signing host's lite username and wait until the
/// People-chain `Resources.Consumers` record exists. Returns the Lite username
/// assigned on chain (including its discriminator).
pub async fn attest(config: &AttestConfig) -> Result<String> {
    let backend =
        IdentityBackendClient::connect(&config.backend_base, config.backend_auth, &config.entropy)
            .await?;

    let verifier = fetch_verifier(&backend.client, &config.backend_base).await?;
    let registration = build_lite_registration(&config.entropy, verifier, &config.username_base)
        .map_err(|reason| anyhow::anyhow!("failed to build registration params: {reason}"))?;
    debug!(
        candidate = %registration.candidate_account_id,
        "attesting lite username '{}'",
        config.username_base
    );

    submit_registration(
        &backend,
        &config.backend_base,
        &config.username_base,
        &registration,
    )
    .await?;

    let storage_key = format!(
        "0x{}",
        hex::encode(resources_consumers_storage_key(
            &registration.candidate_public_key
        ))
    );
    let identity = wait_for_consumer_record(&config.people_ws, &storage_key).await?;
    debug!("lite username registered and confirmed on-chain");
    identity
        .lite_username
        .context("registered People-chain identity has no Lite username")
}

/// Resolve the on-chain Lite username for an already-attested signer.
///
/// Older CLI account records stored the requested username base rather than
/// the final `name.discriminator` assigned by the People chain. Reading the
/// consumer record repairs those records without re-attesting the account.
pub async fn registered_lite_username(people_ws: &str, entropy: &[u8]) -> Result<String> {
    let identity = derive_identity_keypair(entropy)
        .map_err(|err| anyhow::anyhow!("uid.dot identity derivation failed: {err}"))?;
    let storage_key = format!(
        "0x{}",
        hex::encode(resources_consumers_storage_key(&identity.public.to_bytes()))
    );
    let value = query_storage(people_ws, &storage_key)
        .await?
        .context("attested signer has no Resources.Consumers record")?;
    decode_identity_hex(&value)?
        .lite_username
        .context("registered People-chain identity has no Lite username")
}

/// Probe the People chain for the bare root and canonical RFC-0022 `uid.dot`
/// identity account, printing any `Resources.Consumers` record. Used to
/// confirm a pre-onboarded account.
pub async fn check_identity(people_ws: &str, entropy: &[u8]) -> Result<()> {
    let root = derive_root_keypair_from_entropy(entropy)
        .map_err(|err| anyhow::anyhow!("invalid entropy: {err}"))?;
    let identity = derive_identity_keypair(entropy)
        .map_err(|err| anyhow::anyhow!("uid.dot identity derivation failed: {err}"))?;

    for (label, public) in [
        ("<root>", root.public.to_bytes()),
        (
            "//product//uid.dot/index_bytes(0)",
            identity.public.to_bytes(),
        ),
    ] {
        let key = format!(
            "0x{}",
            hex::encode(resources_consumers_storage_key(&public))
        );
        let address = product_public_key_to_address(public);
        match query_storage(people_ws, &key).await {
            Ok(Some(value)) => {
                let decoded = hex::decode(value.strip_prefix("0x").unwrap_or(&value))
                    .ok()
                    .and_then(|bytes| decode_people_identity(&bytes).ok());
                let username = decoded
                    .and_then(|id| id.full_username.or(id.lite_username))
                    .unwrap_or_else(|| "<record present, no username>".to_string());
                println!("IDENTITY_FOUND path={label} account={address} username={username}");
            }
            Ok(None) => println!("IDENTITY_NONE path={label} account={address}"),
            Err(err) => println!("IDENTITY_ERROR path={label} account={address} error={err}"),
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
    backend: &IdentityBackendClient,
    backend_base: &str,
    username_base: &str,
    reg: &truapi_server::host_logic::attestation::LiteRegistration,
) -> Result<()> {
    let url = format!("{backend_base}/usernames");
    let body = json!({
        "username": username_base,
        "candidateAccountId": reg.candidate_account_id,
        "candidateSignature": hex0x(&reg.candidate_signature),
        "ringVrfKey": hex0x(&reg.ring_vrf_key),
        "proofOfOwnership": hex0x(&reg.proof_of_ownership),
        "identifierKey": hex0x(&reg.identifier_key),
        "consumerRegistrationSignature": hex0x(&reg.consumer_registration_signature),
    });
    let response = backend
        .request(reqwest::Method::POST, &url)
        .json(&body)
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
        warn!(%status, "username already registered; confirming on-chain");
        return Ok(());
    }
    bail!("username registration failed ({status}): {text}");
}

/// HTTP access to an identity backend, including its optional proof-based JWT.
struct IdentityBackendClient {
    client: reqwest::Client,
    base_url: String,
    authorization: Option<String>,
}

impl IdentityBackendClient {
    async fn connect(
        backend_base: &str,
        auth: IdentityBackendAuth,
        entropy: &[u8],
    ) -> Result<Self> {
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(30))
            .build()?;
        let authorization = match auth {
            IdentityBackendAuth::None => None,
            IdentityBackendAuth::Jwt => Some(issue_jwt(&client, backend_base, entropy).await?),
        };
        Ok(Self {
            client,
            base_url: backend_base.to_string(),
            authorization,
        })
    }

    fn url(&self, path: &str) -> String {
        format!("{}{path}", self.base_url)
    }

    fn availability_url(&self) -> String {
        let url = self.url("/usernames/available");
        if self.authorization.is_some() {
            format!("{url}?version=v1")
        } else {
            url
        }
    }

    fn request(&self, method: reqwest::Method, url: &str) -> reqwest::RequestBuilder {
        let request = self.client.request(method, url);
        match &self.authorization {
            Some(token) => request.bearer_auth(token),
            None => request,
        }
    }
}

/// Prove control of the signing host's `uid.dot` key and obtain a backend JWT.
async fn issue_jwt(client: &reqwest::Client, backend_base: &str, entropy: &[u8]) -> Result<String> {
    let challenge_url = format!("{backend_base}/auth/challenges");
    let challenge_b64 = client
        .post(&challenge_url)
        .send()
        .await
        .with_context(|| format!("POST {challenge_url}"))?
        .error_for_status()
        .with_context(|| format!("identity backend challenge request failed at {challenge_url}"))?
        .json::<Value>()
        .await
        .context("decoding identity backend challenge response")?
        .get("challenge")
        .and_then(Value::as_str)
        .context("identity backend challenge response missing 'challenge'")?
        .to_string();
    let challenge = base64::engine::general_purpose::STANDARD
        .decode(&challenge_b64)
        .context("identity backend challenge is not base64")?;
    let body = b"{}";
    let (client_id, proof) = identity_proof(entropy, &challenge, body)?;
    let token_url = format!("{backend_base}/auth/token");
    client
        .post(&token_url)
        .header(
            "Auth-ClientId",
            base64::engine::general_purpose::STANDARD.encode(client_id),
        )
        .header(
            "Auth-ClientProof",
            base64::engine::general_purpose::STANDARD.encode(proof),
        )
        .header("Auth-Challenge", challenge_b64)
        .body(body.to_vec())
        .send()
        .await
        .with_context(|| format!("POST {token_url}"))?
        .error_for_status()
        .with_context(|| format!("identity backend token request failed at {token_url}"))?
        .json::<Value>()
        .await
        .context("decoding identity backend token response")?
        .get("token")
        .and_then(Value::as_str)
        .map(str::to_owned)
        .context("identity backend token response missing 'token'")
}

/// Build the proof required by the identity backend token endpoint.
fn identity_proof(entropy: &[u8], challenge: &[u8], body: &[u8]) -> Result<([u8; 32], [u8; 64])> {
    let identity = derive_identity_keypair(entropy)
        .map_err(|err| anyhow::anyhow!("uid.dot identity derivation failed: {err}"))?;
    let client_id = identity.public.to_bytes();
    let mut hasher = Sha256::new();
    hasher.update(challenge);
    hasher.update(client_id);
    hasher.update(Sha256::digest(body));
    let message: [u8; 32] = hasher.finalize().into();
    let proof = identity
        .secret
        .sign_simple(b"substrate", &message, &identity.public)
        .to_bytes();
    Ok((client_id, proof))
}

fn hex0x(bytes: &[u8]) -> String {
    format!("0x{}", hex::encode(bytes))
}

async fn wait_for_consumer_record(
    people_ws: &str,
    storage_key: &str,
) -> Result<truapi_server::host_logic::identity::PeopleIdentity> {
    // First-time lite registration is backend-async and can lag the HTTP
    // response. The record is permanent once written, so later runs resolve on
    // the first poll.
    const MAX_ATTEMPTS: usize = 10;
    for attempt in 1..=MAX_ATTEMPTS {
        match query_storage(people_ws, storage_key).await {
            Ok(Some(value)) => {
                crate::terminal_ui::update_activity(
                    "signer",
                    "Setting up signer",
                    Some("People-chain identity ready".to_string()),
                    crate::terminal_ui::ActivityState::Running,
                );
                return decode_identity_hex(&value);
            }
            Ok(None) => {
                crate::terminal_ui::update_activity(
                    "signer",
                    "Setting up signer",
                    Some(format!(
                        "Waiting for People-chain identity · attempt {attempt}/{MAX_ATTEMPTS}"
                    )),
                    crate::terminal_ui::ActivityState::Running,
                );
                debug!("Resources.Consumers poll {attempt}/{MAX_ATTEMPTS}: empty");
            }
            Err(err) => warn!(%err, "Resources.Consumers poll attempt {attempt} failed"),
        }
        if attempt < MAX_ATTEMPTS {
            tokio::time::sleep(Duration::from_secs(4)).await;
        }
    }
    bail!("Resources.Consumers record did not appear after attestation")
}

fn decode_identity_hex(value: &str) -> Result<truapi_server::host_logic::identity::PeopleIdentity> {
    let bytes = hex::decode(value.strip_prefix("0x").unwrap_or(value))
        .context("Resources.Consumers value is not valid hex")?;
    decode_people_identity(&bytes).map_err(anyhow::Error::msg)
}

/// One `state_getStorage` request over a fresh RPC connection; returns the value
/// hex when present.
async fn query_storage(people_ws: &str, storage_key: &str) -> Result<Option<String>> {
    let rpc = RpcClient::from_insecure_url(people_ws)
        .await
        .with_context(|| format!("connect {people_ws}"))?;
    let value = rpc
        .request::<Value>("state_getStorage", rpc_params![storage_key])
        .await
        .context("rpc state_getStorage")?;
    Ok(value.as_str().map(str::to_string))
}
