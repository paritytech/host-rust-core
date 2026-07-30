//! Automatic iOS-compatible contact-request acceptance for signing hosts.

use std::collections::{HashMap, HashSet, VecDeque};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result, bail};
use rand::RngCore;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use subxt_rpcs::client::{RpcClient, rpc_params};
use tracing::{debug, warn};
use truapi_server::host_logic::chat::{
    build_chat_acceptance_statement, chat_request_discovery_topic, chat_statement_priority,
    decode_incoming_chat_request, validate_peer_identity,
};
use truapi_server::host_logic::product_account::product_public_key_to_address;
use truapi_server::host_logic::statement_store::{
    SUBMIT_STATEMENT_METHOD, SUBSCRIBE_STATEMENT_METHOD, UNSUBSCRIBE_STATEMENT_METHOD,
    decode_statement_data, parse_new_statements_result,
};
use truapi_server::statement_allowance as alloc;

use crate::attestation;
use crate::network::NetworkConfig;
use crate::terminal_ui::{self, SystemEvent};

const RECONNECT_DELAY: Duration = Duration::from_secs(3);
const ALLOWANCE_PROPAGATION_ATTEMPTS: usize = 5;
const ALLOWANCE_PROPAGATION_DELAY: Duration = Duration::from_secs(1);
const ACCEPTED_REQUEST_LIMIT: usize = 256;
const STATE_VERSION: u32 = 2;

/// Run until cancelled, reconnecting the statement subscription as needed.
pub async fn monitor(network: NetworkConfig, entropy: Vec<u8>, state_directory: Option<PathBuf>) {
    let identity = match attestation::registered_chat_identity(network.people_ws, &entropy).await {
        Ok(registered) => registered.chat,
        Err(error) => {
            warn!(%error, "chat-request monitor could not resolve a registered identity");
            return;
        }
    };
    let topic = chat_request_discovery_topic(identity.statement_account_id);
    let state_path = state_directory.map(|directory| {
        directory.join(format!(
            "accepted-chat-requests-{}.json",
            hex::encode(identity.statement_account_id)
        ))
    });
    let mut accepted = AcceptedRequestStore::load(state_path);

    loop {
        if let Err(error) =
            monitor_connection(network, &entropy, &identity, topic, &mut accepted).await
        {
            debug!(%error, "chat-request subscription disconnected");
        }
        tokio::time::sleep(RECONNECT_DELAY).await;
    }
}

async fn monitor_connection(
    network: NetworkConfig,
    entropy: &[u8],
    identity: &truapi_server::host_logic::chat::ChatIdentity,
    topic: [u8; 32],
    accepted: &mut AcceptedRequestStore,
) -> Result<()> {
    let rpc = RpcClient::from_insecure_url(network.people_ws)
        .await
        .with_context(|| format!("connect {}", network.people_ws))?;
    let filter = json!({
        "matchAll": [format!("0x{}", hex::encode(topic))]
    });
    let mut subscription = rpc
        .subscribe::<Value>(
            SUBSCRIBE_STATEMENT_METHOD,
            rpc_params![filter],
            UNSUBSCRIBE_STATEMENT_METHOD,
        )
        .await
        .context("subscribe to chat-request discovery topic")?;
    debug!(
        account = %hex::encode(identity.statement_account_id),
        "chat-request monitor subscribed"
    );

    while let Some(item) = subscription.next().await {
        let result = item.context("chat-request subscription item")?;
        let page = parse_new_statements_result("chat-requests".to_string(), &result)
            .map_err(anyhow::Error::msg)?;
        for statement in page.statements {
            if let Err(error) =
                handle_statement(network, entropy, identity, &rpc, accepted, &statement).await
            {
                debug!(%error, "ignored invalid or unaccepted chat request");
            }
        }
    }
    bail!("chat-request subscription ended")
}

async fn handle_statement(
    network: NetworkConfig,
    entropy: &[u8],
    own: &truapi_server::host_logic::chat::ChatIdentity,
    rpc: &RpcClient,
    accepted: &mut AcceptedRequestStore,
    statement: &[u8],
) -> Result<()> {
    let data = decode_statement_data(statement).map_err(anyhow::Error::msg)?;
    let request = decode_incoming_chat_request(&data, own).map_err(anyhow::Error::msg)?;
    if accepted.contains(&request.request_id) {
        return Ok(());
    }
    if accepted.predates_activation(request.timestamp_ms) {
        debug!(
            request_id = %request.request_id,
            timestamp_ms = request.timestamp_ms,
            "ignoring historical chat request from before CLI monitoring was activated"
        );
        accepted.remember_seen(request.request_id);
        return Ok(());
    }

    let peer = attestation::people_identity(network.people_ws, request.peer_account_id).await?;
    validate_peer_identity(&request, own, peer.identifier_key).map_err(anyhow::Error::msg)?;
    let username = peer
        .full_username
        .or(peer.lite_username)
        .unwrap_or_else(|| product_public_key_to_address(request.peer_account_id));
    terminal_ui::output_event(SystemEvent::ChatRequestDetected {
        username: username.clone(),
    });

    let result = async {
        ensure_statement_allowance(network.people_ws, entropy, own.statement_account_id).await?;
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .context("system clock before Unix epoch")?;
        let priority = accepted.next_priority(
            request.peer_account_id,
            chat_statement_priority(now.as_secs()),
        );
        let statement = build_chat_acceptance_statement(
            own,
            &request,
            peer.identifier_key,
            random_uuid(),
            random_uuid(),
            now.as_millis()
                .try_into()
                .context("chat timestamp overflow")?,
            priority,
        )
        .map_err(anyhow::Error::msg)?;
        submit_statement(rpc, statement).await?;
        Ok::<u64, anyhow::Error>(priority)
    }
    .await;

    match result {
        Ok(priority) => {
            accepted.remember(request.request_id, request.peer_account_id, priority);
            terminal_ui::output_event(SystemEvent::ChatRequestAccepted { username });
            Ok(())
        }
        Err(error) => {
            terminal_ui::output_event(SystemEvent::ChatRequestFailed {
                username,
                reason: error.to_string(),
            });
            Err(error)
        }
    }
}

async fn ensure_statement_allowance(
    people_ws: &str,
    entropy: &[u8],
    account: [u8; 32],
) -> Result<()> {
    let rpc = alloc::rpc::RpcClient::connect(people_ws)
        .await
        .map_err(anyhow::Error::msg)?;
    let metadata = alloc::fetch_metadata(&rpc)
        .await
        .map_err(anyhow::Error::msg)?;
    let chain_state = alloc::fetch_chain_state(&rpc)
        .await
        .map_err(anyhow::Error::msg)?;
    let bandersnatch = alloc::bandersnatch_entropy(entropy);
    let current = alloc::ring::read_current_ring_index(&rpc)
        .await
        .map_err(anyhow::Error::msg)?;
    let ring = alloc::find_including_ring(&rpc, &metadata, bandersnatch, current)
        .await
        .map_err(anyhow::Error::msg)?
        .context("signing account is not a LitePeople ring member")?;
    let period = alloc::slot::current_period(
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .context("system clock before Unix epoch")?
            .as_secs(),
    );
    alloc::register_statement_account(
        &rpc,
        &metadata,
        &chain_state,
        bandersnatch,
        alloc::RegistrationParams {
            target: &account,
            period,
            ring: &ring,
            reuse_existing: true,
        },
    )
    .await
    .map_err(|error| anyhow::anyhow!("chat statement allowance failed: {error}"))?;
    Ok(())
}

async fn submit_statement(rpc: &RpcClient, statement: Vec<u8>) -> Result<()> {
    let encoded = format!("0x{}", hex::encode(statement));
    for attempt in 1..=ALLOWANCE_PROPAGATION_ATTEMPTS {
        let result = rpc
            .request::<Value>(SUBMIT_STATEMENT_METHOD, rpc_params![encoded.clone()])
            .await
            .context("submit chat acceptance statement")?;
        match result.get("status").and_then(Value::as_str) {
            Some("new") | Some("known") => return Ok(()),
            _ if result.get("reason").and_then(Value::as_str) == Some("noAllowance")
                && attempt < ALLOWANCE_PROPAGATION_ATTEMPTS =>
            {
                tokio::time::sleep(ALLOWANCE_PROPAGATION_DELAY).await;
            }
            _ => bail!("chat acceptance statement rejected: {result}"),
        }
    }
    unreachable!("bounded chat statement submission always returns")
}

fn random_uuid() -> String {
    let mut bytes = [0u8; 16];
    rand::rngs::OsRng.fill_bytes(&mut bytes);
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    let hex = hex::encode(bytes);
    format!(
        "{}-{}-{}-{}-{}",
        &hex[..8],
        &hex[8..12],
        &hex[12..16],
        &hex[16..20],
        &hex[20..]
    )
}

#[derive(Default, Serialize, Deserialize)]
struct AcceptedRequestState {
    version: u32,
    /// First activation of CLI chat monitoring for this identity.
    ///
    /// Requests older than this belong to the user's pre-existing iOS contact
    /// history. The CLI has no access to the phone's local contact database,
    /// so replaying those statements as new requests would be misleading.
    #[serde(default)]
    activated_at_ms: u64,
    request_ids: VecDeque<String>,
    #[serde(default)]
    last_priority_by_peer: HashMap<String, u64>,
}

struct AcceptedRequestStore {
    path: Option<PathBuf>,
    state: AcceptedRequestState,
    ids: HashSet<String>,
}

impl AcceptedRequestStore {
    fn load(path: Option<PathBuf>) -> Self {
        let state = match path.as_deref().and_then(read_state) {
            Some(state) if state.version == STATE_VERSION => state,
            Some(state) if state.version == 1 => AcceptedRequestState {
                // Version 1 recorded submissions carrying a double-wrapped
                // ciphertext that iOS could not decrypt. Retry those requests
                // after upgrading instead of preserving false success.
                version: STATE_VERSION,
                request_ids: VecDeque::new(),
                activated_at_ms: 0,
                last_priority_by_peer: state.last_priority_by_peer,
            },
            _ => AcceptedRequestState {
                version: STATE_VERSION,
                activated_at_ms: current_unix_millis(),
                request_ids: VecDeque::new(),
                last_priority_by_peer: HashMap::new(),
            },
        };
        let ids = state.request_ids.iter().cloned().collect();
        Self { path, state, ids }
    }

    fn contains(&self, request_id: &str) -> bool {
        self.ids.contains(request_id)
    }

    fn predates_activation(&self, request_timestamp_ms: u64) -> bool {
        request_timestamp_ms < self.state.activated_at_ms
    }

    fn next_priority(&self, peer_account_id: [u8; 32], timestamp_priority: u64) -> u64 {
        self.state
            .last_priority_by_peer
            .get(&hex::encode(peer_account_id))
            .map_or(timestamp_priority, |last| {
                timestamp_priority.max(last.saturating_add(1))
            })
    }

    fn remember(&mut self, request_id: String, peer_account_id: [u8; 32], priority: u64) {
        if !self.remember_id(request_id) {
            return;
        }
        let peer_key = hex::encode(peer_account_id);
        self.state
            .last_priority_by_peer
            .insert(peer_key.clone(), priority);
        if self.state.last_priority_by_peer.len() > ACCEPTED_REQUEST_LIMIT
            && let Some(oldest) = self
                .state
                .last_priority_by_peer
                .keys()
                .find(|key| key.as_str() != peer_key)
                .cloned()
        {
            self.state.last_priority_by_peer.remove(&oldest);
        }
        if let Err(error) = self.save() {
            warn!(%error, "could not persist accepted chat request");
        }
    }

    fn remember_seen(&mut self, request_id: String) {
        if self.remember_id(request_id)
            && let Err(error) = self.save()
        {
            warn!(%error, "could not persist historical chat request");
        }
    }

    fn remember_id(&mut self, request_id: String) -> bool {
        if !self.ids.insert(request_id.clone()) {
            return false;
        }
        self.state.request_ids.push_back(request_id);
        while self.state.request_ids.len() > ACCEPTED_REQUEST_LIMIT {
            if let Some(removed) = self.state.request_ids.pop_front() {
                self.ids.remove(&removed);
            }
        }
        true
    }

    fn save(&self) -> Result<()> {
        let Some(path) = &self.path else {
            return Ok(());
        };
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).with_context(|| format!("create {}", parent.display()))?;
        }
        let bytes = serde_json::to_vec_pretty(&self.state)?;
        let temporary = path.with_extension("json.tmp");
        fs::write(&temporary, bytes).with_context(|| format!("write {}", temporary.display()))?;
        fs::rename(&temporary, path).with_context(|| format!("replace {}", path.display()))
    }
}

fn current_unix_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
        .try_into()
        .unwrap_or(u64::MAX)
}

fn read_state(path: &Path) -> Option<AcceptedRequestState> {
    match fs::read(path) {
        Ok(bytes) => match serde_json::from_slice(&bytes) {
            Ok(state) => Some(state),
            Err(error) => {
                warn!(%error, path = %path.display(), "invalid chat-request state");
                None
            }
        },
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => None,
        Err(error) => {
            warn!(%error, path = %path.display(), "could not read chat-request state");
            None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepted_request_store_is_bounded_and_round_trips() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("chat-requests.json");
        let mut store = AcceptedRequestStore::load(Some(path.clone()));
        for index in 0..(ACCEPTED_REQUEST_LIMIT + 4) {
            store.remember(format!("request-{index}"), [index as u8; 32], index as u64);
        }

        let restored = AcceptedRequestStore::load(Some(path));

        assert_eq!(restored.state.request_ids.len(), ACCEPTED_REQUEST_LIMIT);
        assert!(!restored.contains("request-0"));
        assert!(restored.contains(&format!("request-{}", ACCEPTED_REQUEST_LIMIT + 3)));
    }

    #[test]
    fn acceptance_priority_increments_within_one_peer_session() {
        let mut store = AcceptedRequestStore::load(None);
        let timestamp_priority = chat_statement_priority(1_763_164_800 + 42);
        store.remember("first".to_string(), [7; 32], timestamp_priority);

        assert_eq!(
            store.next_priority([7; 32], timestamp_priority),
            timestamp_priority + 1
        );
        assert_eq!(
            store.next_priority([8; 32], timestamp_priority),
            timestamp_priority
        );
    }

    #[test]
    fn historical_request_is_remembered_without_consuming_peer_priority() {
        let mut store = AcceptedRequestStore::load(None);
        store.state.activated_at_ms = 100;

        assert!(store.predates_activation(99));
        assert!(!store.predates_activation(100));
        store.remember_seen("historical".to_string());

        assert!(store.contains("historical"));
        assert!(store.state.last_priority_by_peer.is_empty());
    }

    #[test]
    fn version_one_state_retries_double_wrapped_acceptances() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("chat-requests.json");
        fs::write(
            &path,
            br#"{
                "version": 1,
                "request_ids": ["failed-acceptance"],
                "last_priority_by_peer": {"0707070707070707070707070707070707070707070707070707070707070707": 42}
            }"#,
        )
        .unwrap();

        let store = AcceptedRequestStore::load(Some(path));

        assert_eq!(store.state.version, STATE_VERSION);
        assert_eq!(store.state.activated_at_ms, 0);
        assert!(!store.contains("failed-acceptance"));
        assert_eq!(store.next_priority([7; 32], 1), 43);
    }

    #[test]
    fn generated_message_ids_are_uuid_v4_shaped() {
        let id = random_uuid();

        assert_eq!(id.len(), 36);
        assert_eq!(&id[14..15], "4");
        assert!(matches!(&id[19..20], "8" | "9" | "a" | "b"));
    }
}
