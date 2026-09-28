//! Preimage lookup for the CLI host: the blob behind a key, read from a Bulletin node by CID.
//!
//! Transaction storage serves every blob a node retains over bitswap, and the node exposes that
//! on its JSON-RPC as `bitswap_v1_get(cid)`. The CID is fixed by the key: CIDv1, the `raw`
//! codec, and the blake2b-256 multihash that is the preimage key itself. A lookup is therefore
//! one round trip to the endpoint the network preset already names for the chain, and the host
//! needs no IPFS stack of its own.
//!
//! A subscription emits the current answer at once. On a miss it keeps asking every
//! [`POLL_INTERVAL`] until the blob appears, since a submission from another host lands within
//! a block or two, and it ends once it has delivered a value. A node that cannot be reached is
//! reported as a miss as well, never as the end of the subscription, so a product waiting on a
//! blob survives a transport failure. Every value is checked against the key before it is
//! emitted.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use async_trait::async_trait;
use futures::stream::{self, BoxStream, StreamExt};
use serde_json::Value;
use sp_crypto_hashing::blake2_256;
use subxt_rpcs::client::{RpcClient, rpc_params};
use tokio::sync::Mutex as AsyncMutex;
use tracing::{debug, info, warn};
use truapi::latest as api;

/// How long a miss waits before asking the node again: about one Bulletin block.
const POLL_INTERVAL: Duration = Duration::from_secs(6);
/// Bound on one round trip to the node.
const RPC_TIMEOUT: Duration = Duration::from_secs(20);

/// Where blobs are fetched from, by CID. The seam the subscription logic is tested through.
#[async_trait]
pub trait BlobSource: Send + Sync {
    /// The blob stored under `cid`, or `None` when the source does not hold it.
    async fn get(&self, cid: &str) -> Result<Option<Vec<u8>>, String>;
}

/// `bitswap_v1_get` on a Bulletin node's JSON-RPC. The connection is opened on first use and
/// dropped after a transport failure, so the next call reconnects.
pub struct BitswapRpc {
    url: &'static str,
    client: AsyncMutex<Option<RpcClient>>,
}

impl BitswapRpc {
    pub fn new(url: &'static str) -> Self {
        Self {
            url,
            client: AsyncMutex::new(None),
        }
    }

    async fn client(&self) -> Result<RpcClient, String> {
        let mut slot = self.client.lock().await;
        if let Some(client) = slot.as_ref() {
            return Ok(client.clone());
        }
        let client = tokio::time::timeout(RPC_TIMEOUT, RpcClient::from_insecure_url(self.url))
            .await
            .map_err(|_| format!("connecting to {} timed out", self.url))?
            .map_err(|err| format!("connecting to {}: {err}", self.url))?;
        *slot = Some(client.clone());
        Ok(client)
    }

    async fn disconnect(&self) {
        *self.client.lock().await = None;
    }
}

#[async_trait]
impl BlobSource for BitswapRpc {
    async fn get(&self, cid: &str) -> Result<Option<Vec<u8>>, String> {
        let client = self.client().await?;
        let request = client.request::<Value>("bitswap_v1_get", rpc_params![cid]);
        let value = match tokio::time::timeout(RPC_TIMEOUT, request).await {
            Ok(Ok(value)) => value,
            // A CID the node does not hold is answered with a call error, not with null. Any
            // other call error (the method missing on this node, say) is reported, or every
            // lookup would look like a miss for ever.
            Ok(Err(subxt_rpcs::Error::User(error))) => {
                if error.message.to_ascii_lowercase().contains("not found") {
                    debug!(cid, message = %error.message, "bitswap_v1_get: not held");
                    return Ok(None);
                }
                return Err(format!("bitswap_v1_get: {}", error.message));
            }
            Ok(Err(error)) => {
                self.disconnect().await;
                return Err(format!("bitswap_v1_get: {error}"));
            }
            Err(_) => {
                self.disconnect().await;
                return Err("bitswap_v1_get timed out".to_string());
            }
        };
        match value {
            Value::String(hex) => hex::decode(hex.trim_start_matches("0x"))
                .map(Some)
                .map_err(|err| format!("bitswap_v1_get: response is not hex: {err}")),
            Value::Null => Ok(None),
            other => Err(format!("bitswap_v1_get: unexpected response {other}")),
        }
    }
}

/// Lookups over one blob source: the CID for each key, the check that what comes back hashes to
/// it, and a cache of what has been read, so a repeated lookup answers from memory. The cache
/// is not bounded: a blob is at most a few kilobytes and a host session reads a handful, so a
/// bound would only add a policy to explain.
pub struct BulletinLookup<S> {
    source: S,
    cache: Mutex<HashMap<[u8; 32], Vec<u8>>>,
    poll_interval: Duration,
}

impl<S: BlobSource + 'static> BulletinLookup<S> {
    pub fn new(source: S) -> Self {
        Self::with_poll_interval(source, POLL_INTERVAL)
    }

    fn with_poll_interval(source: S, poll_interval: Duration) -> Self {
        Self {
            source,
            cache: Mutex::new(HashMap::new()),
            poll_interval,
        }
    }

    /// The stream `PreimageHost::lookup_preimage` returns for `key`: the current answer at once,
    /// then the value once it can be read, then the end.
    pub fn subscribe(
        self: &Arc<Self>,
        key: Vec<u8>,
    ) -> BoxStream<'static, Result<Option<Vec<u8>>, api::GenericError>> {
        let Ok(key) = <[u8; 32]>::try_from(key.as_slice()) else {
            // Not a blake2b-256 digest, so nothing can ever hash to it.
            return stream::once(async { Ok(None) }).boxed();
        };
        if let Some(value) = self.cached(&key) {
            return stream::once(async move { Ok(Some(value)) }).boxed();
        }
        let lookup = Arc::clone(self);
        let cid = cid_for(&key);
        stream::unfold(Some(0u32), move |attempt| {
            let lookup = Arc::clone(&lookup);
            let cid = cid.clone();
            async move {
                let mut attempt = attempt?;
                loop {
                    if attempt > 0 {
                        tokio::time::sleep(lookup.poll_interval).await;
                    }
                    if let Some(value) = lookup.read(&cid, &key, attempt).await {
                        return Some((Ok(Some(value)), None));
                    }
                    if attempt == 0 {
                        return Some((Ok(None), Some(1)));
                    }
                    attempt += 1;
                }
            }
        })
        .boxed()
    }

    fn cached(&self, key: &[u8; 32]) -> Option<Vec<u8>> {
        self.cache
            .lock()
            .expect("preimage cache poisoned")
            .get(key)
            .cloned()
    }

    /// One attempt: the blob if the source holds it and it hashes to `key`.
    async fn read(&self, cid: &str, key: &[u8; 32], attempt: u32) -> Option<Vec<u8>> {
        match self.source.get(cid).await {
            Ok(Some(value)) if blake2_256(&value) == *key => {
                info!(key = %hex::encode(key), size = value.len(), "preimage read from Bulletin");
                self.cache
                    .lock()
                    .expect("preimage cache poisoned")
                    .insert(*key, value.clone());
                Some(value)
            }
            Ok(Some(_)) => {
                warn!(key = %hex::encode(key), "preimage source returned bytes that do not hash to the key");
                None
            }
            Ok(None) => None,
            Err(reason) => {
                // Reported once per subscription; the poll keeps going and reconnects.
                if attempt == 0 {
                    warn!(key = %hex::encode(key), %reason, "preimage lookup failed, still trying");
                } else {
                    debug!(key = %hex::encode(key), %reason, "preimage lookup failed, still trying");
                }
                None
            }
        }
    }
}

/// The CID transaction storage serves a blob under: CIDv1 (0x01), the `raw` codec (0x55), a
/// blake2b-256 multihash (code 0xb220 as a varint, then the 32-byte length) of the key itself;
/// base32 lower with the multibase `b` prefix, as `bitswap_v1_get` takes it.
fn cid_for(key: &[u8; 32]) -> String {
    const ALPHABET: &[u8; 32] = b"abcdefghijklmnopqrstuvwxyz234567";
    let mut bytes = vec![0x01, 0x55, 0xa0, 0xe4, 0x02, 0x20];
    bytes.extend_from_slice(key);
    let mut cid = String::from("b");
    let (mut buffer, mut bits) = (0u32, 0u32);
    for byte in bytes {
        buffer = (buffer << 8) | u32::from(byte);
        bits += 8;
        while bits >= 5 {
            cid.push(ALPHABET[((buffer >> (bits - 5)) & 31) as usize] as char);
            bits -= 5;
        }
    }
    if bits > 0 {
        cid.push(ALPHABET[((buffer << (5 - bits)) & 31) as usize] as char);
    }
    cid
}

#[cfg(test)]
mod tests {
    use std::collections::VecDeque;

    use super::*;

    /// A source that answers from a script, one entry per call, and counts the calls.
    struct Scripted {
        answers: Mutex<VecDeque<Result<Option<Vec<u8>>, String>>>,
        calls: Mutex<u32>,
    }

    impl Scripted {
        fn new(answers: Vec<Result<Option<Vec<u8>>, String>>) -> Self {
            Self {
                answers: Mutex::new(answers.into()),
                calls: Mutex::new(0),
            }
        }
    }

    #[async_trait]
    impl BlobSource for Scripted {
        async fn get(&self, _cid: &str) -> Result<Option<Vec<u8>>, String> {
            *self.calls.lock().unwrap() += 1;
            self.answers
                .lock()
                .unwrap()
                .pop_front()
                .expect("scripted source asked more often than scripted")
        }
    }

    fn blob() -> Vec<u8> {
        b"coffer bulletin probe".to_vec()
    }

    fn lookup(answers: Vec<Result<Option<Vec<u8>>, String>>) -> Arc<BulletinLookup<Scripted>> {
        Arc::new(BulletinLookup::with_poll_interval(
            Scripted::new(answers),
            Duration::from_millis(1),
        ))
    }

    async fn events(lookup: &Arc<BulletinLookup<Scripted>>, key: &[u8]) -> Vec<Option<Vec<u8>>> {
        lookup
            .subscribe(key.to_vec())
            .map(|item| item.expect("lookups report failures as misses"))
            .collect()
            .await
    }

    #[tokio::test]
    async fn a_held_blob_is_emitted_at_once_and_the_subscription_ends() {
        let lookup = lookup(vec![Ok(Some(blob()))]);
        assert_eq!(
            events(&lookup, &blake2_256(&blob())).await,
            vec![Some(blob())]
        );
    }

    #[tokio::test]
    async fn a_miss_is_reported_at_once_then_the_blob_when_it_lands_then_the_end() {
        // The product hears the miss immediately, so it can show "waiting", and is not asked
        // to resubscribe: the same subscription delivers the blob once another host's
        // submission has landed.
        let lookup = lookup(vec![Ok(None), Ok(None), Ok(Some(blob()))]);
        assert_eq!(
            events(&lookup, &blake2_256(&blob())).await,
            vec![None, Some(blob())]
        );
        assert_eq!(*lookup.source.calls.lock().unwrap(), 3);
    }

    #[tokio::test]
    async fn bytes_that_do_not_hash_to_the_key_are_never_emitted() {
        let lookup = lookup(vec![Ok(Some(b"forged".to_vec())), Ok(Some(blob()))]);
        assert_eq!(
            events(&lookup, &blake2_256(&blob())).await,
            vec![None, Some(blob())]
        );
    }

    #[tokio::test]
    async fn a_failing_source_is_a_miss_not_the_end_of_the_subscription() {
        let lookup = lookup(vec![Err("node down".to_string()), Ok(Some(blob()))]);
        assert_eq!(
            events(&lookup, &blake2_256(&blob())).await,
            vec![None, Some(blob())]
        );
    }

    #[tokio::test]
    async fn a_repeated_lookup_answers_from_memory() {
        let lookup = lookup(vec![Ok(Some(blob()))]);
        let key = blake2_256(&blob());
        events(&lookup, &key).await;
        assert_eq!(events(&lookup, &key).await, vec![Some(blob())]);
        assert_eq!(*lookup.source.calls.lock().unwrap(), 1);
    }

    #[tokio::test]
    async fn a_key_that_is_not_a_digest_is_a_miss_and_the_end() {
        let lookup = lookup(vec![]);
        assert_eq!(events(&lookup, &[9]).await, vec![None]);
    }

    #[test]
    fn cid_is_cidv1_raw_blake2b_256_in_base32() {
        // Checked against Paseo Bulletin: bitswap_v1_get with this CID returns the blob whose
        // blake2b-256 is the key.
        let mut key = [0u8; 32];
        key.copy_from_slice(
            &hex::decode("0bd1bb57e3f9ea801956a770fe1068f950383547aca45e1d3d354d57d014cb0c")
                .unwrap(),
        );
        assert_eq!(
            cid_for(&key),
            "bafk2bzaceaf5do2x4p46vaazk2txb7qqnd4vaobvi6wkixq5hu2u2v6qctfqy"
        );
    }
}
