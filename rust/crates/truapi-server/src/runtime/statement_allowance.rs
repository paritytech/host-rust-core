//! On-chain statement-store allowance registration (`set_statement_store_account`).
//!
//! Mirrors how an iOS/web client obtains statement-store allowance from the real
//! People chain: build the `Resources.set_statement_store_account` call, prove
//! LitePeople membership with the caller's registry-selected ring-VRF key,
//! and submit the resulting unsigned General (v5) extrinsic. Native only
//! (needs the `verifiable` prover and live chain reads).

pub mod extension;
pub mod extrinsic;
pub mod proof;
pub mod renewal;
pub mod ring;
pub mod rpc;
pub mod slot;

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use futures::FutureExt;
use parity_scale_codec::{Decode, Encode};
use serde_json::{Value, json};
use sp_crypto_hashing::twox_128;
use thiserror::Error;
use tracing::{debug, warn};

use extension::{ChainState, Metadata, MetadataError};
use ring::RingParams;
use rpc::RpcClient;
use slot::{SlotError, SlotSelection};

/// Error while reading chain state, building allowance extrinsics, or waiting
/// for allowance authorization.
#[derive(Debug, Error)]
pub enum StatementAllowanceError {
    /// JSON-RPC transport, request, subscription, or storage hex failure.
    #[error(transparent)]
    Rpc(#[from] rpc::RpcError),
    /// Runtime metadata was missing an expected pallet, call, type, extension,
    /// constant, or could not be decoded.
    #[error(transparent)]
    Metadata(#[from] extension::MetadataError),
    /// Chain RPC returned a value with an unexpected shape.
    #[error(transparent)]
    ChainState(#[from] ChainStateError),
    /// Ring lookup or ring storage decoding failed.
    #[error(transparent)]
    Ring(#[from] ring::RingError),
    /// Slot context, alias, or free-slot selection failed.
    #[error(transparent)]
    Slot(#[from] slot::SlotError),
    /// Ring-VRF proof construction failed.
    #[error(transparent)]
    Proof(#[from] proof::ProofError),
    /// Bulletin allowance polling timed out.
    #[error("timed out waiting for Bulletin authorization")]
    BulletinAuthorizationTimeout,
}

/// Error while decoding generic chain state used by allowance registration.
#[derive(Debug, Error)]
pub enum ChainStateError {
    /// `chain_getBlockHash(0)` did not return a hex string.
    #[error("chain_getBlockHash returned non-string")]
    GenesisHashNotString,
    /// `chain_getBlockHash(0)` returned invalid hex.
    #[error("genesis hex: {0}")]
    GenesisHex(#[source] hex::FromHexError),
    /// Decoded genesis hash was not 32 bytes.
    #[error("genesis hash is {len} bytes, expected 32")]
    GenesisHashLength {
        /// Actual decoded length.
        len: usize,
    },
    /// Runtime JSON lacked an expected u32 field.
    #[error("missing/invalid {field}")]
    MissingU32Field {
        /// Field name.
        field: &'static str,
    },
    /// Bulletin authorization storage failed to decode a field.
    #[error("authorization {field}: {source}")]
    AuthorizationFieldDecode {
        /// Field name.
        field: &'static str,
        /// SCALE decode failure.
        #[source]
        source: parity_scale_codec::Error,
    },
    /// `chain_getHeader` did not contain a block number string.
    #[error("chain_getHeader returned no number")]
    HeaderNumberMissing,
    /// `chain_getHeader.number` was not valid hex.
    #[error("chain_getHeader number: {0}")]
    HeaderNumberParse(#[source] std::num::ParseIntError),
}

/// Fetch and decode the runtime metadata (`state_getMetadata`).
pub async fn fetch_metadata(rpc: &RpcClient) -> Result<Metadata, StatementAllowanceError> {
    let value = rpc.call("state_getMetadata", json!([])).await?;
    let hex_str = value
        .as_str()
        .ok_or(MetadataError::MetadataResultNotString)?;
    let bytes = hex::decode(hex_str.strip_prefix("0x").unwrap_or(hex_str))
        .map_err(MetadataError::MetadataHex)?;
    // `state_getMetadata` may return either the raw `RuntimeMetadataPrefixed`
    // (starts with the `meta` magic) or an OpaqueMetadata wrapper
    // (`Vec<u8>` = compact(len) ‖ bytes). Strip the wrapper only when present.
    const META_MAGIC: [u8; 4] = *b"meta";
    if bytes.get(..4) == Some(&META_MAGIC) {
        Metadata::decode(&bytes)
    } else {
        let inner = Vec::<u8>::decode(&mut &bytes[..]).map_err(MetadataError::OpaqueMetadata)?;
        Metadata::decode(&inner)
    }
}

/// Read the chain's runtime `(specVersion, transactionVersion)`.
pub async fn fetch_runtime_version(rpc: &RpcClient) -> Result<(u32, u32), StatementAllowanceError> {
    let runtime = rpc.call("state_getRuntimeVersion", json!([])).await?;
    Ok((
        json_u32(&runtime, "specVersion")?,
        json_u32(&runtime, "transactionVersion")?,
    ))
}

/// Read the chain's genesis block hash.
pub async fn fetch_genesis_hash(rpc: &RpcClient) -> Result<[u8; 32], StatementAllowanceError> {
    let genesis_hex = rpc.call("chain_getBlockHash", json!([0])).await?;
    let genesis_str = genesis_hex
        .as_str()
        .ok_or(ChainStateError::GenesisHashNotString)?;
    let genesis = hex::decode(genesis_str.strip_prefix("0x").unwrap_or(genesis_str))
        .map_err(ChainStateError::GenesisHex)?;
    let len = genesis.len();
    genesis
        .try_into()
        .map_err(|_| ChainStateError::GenesisHashLength { len }.into())
}

/// Fetch the chain state needed to fill the signed extensions.
pub async fn fetch_chain_state(rpc: &RpcClient) -> Result<ChainState, StatementAllowanceError> {
    let genesis_hash = fetch_genesis_hash(rpc).await?;
    let (spec_version, transaction_version) = fetch_runtime_version(rpc).await?;
    Ok(ChainState {
        spec_version,
        transaction_version,
        genesis_hash,
        nonce: 0,
    })
}

/// An RPC client together with the genesis hash the host routes it by.
///
/// Bundled because the two have to agree and nothing at a call site shows when
/// they do not: that hash keys the chain-context cache and is what a reported
/// divergence is measured against, so pairing a connection with another chain's
/// hash silently attributes one chain's metadata to another.
pub struct ChainClient {
    rpc: RpcClient,
    configured_genesis_hash: [u8; 32],
}

impl ChainClient {
    /// Scope `rpc` to the chain the host routes by `configured_genesis_hash`.
    pub fn new(rpc: RpcClient, configured_genesis_hash: [u8; 32]) -> Self {
        Self {
            rpc,
            configured_genesis_hash,
        }
    }

    /// The underlying client, for reads that do not need the chain's identity.
    pub fn rpc(&self) -> &RpcClient {
        &self.rpc
    }
}

/// Runtime metadata and signed-extension chain state for one chain.
#[derive(Clone)]
pub struct ChainContext {
    /// Decoded runtime metadata.
    pub metadata: Arc<Metadata>,
    /// Chain state filling the standard signed extensions.
    pub state: ChainState,
}

/// Runtime metadata and chain state cached per chain.
///
/// Both are fixed for a given runtime, and a full `state_getMetadata` response
/// is large, so entries are keyed by genesis hash and revalidated with a
/// concurrent `state_getRuntimeVersion` + `chain_getBlockHash(0)` — two small
/// requests in place of a metadata download on every allowance call.
///
/// One entry per chain the host is configured for, so the map needs no eviction
/// policy: it is bounded by that chain set, not by call volume.
#[derive(Default)]
pub struct ChainContextCache {
    entries: Mutex<HashMap<[u8; 32], ChainContext>>,
    /// Held across a miss so concurrent callers do not each download the same
    /// metadata. `chain_runtime` shares one in-flight future for this, which is
    /// tidier, but `Shared` needs a `Clone` output and `StatementAllowanceError`
    /// is not — so the waiters re-check the entry instead.
    downloads: futures::lock::Mutex<()>,
}

impl ChainContextCache {
    /// Metadata and chain state for the chain reached over `rpc`, read from the
    /// chain only when no entry describes the chain as it is now.
    ///
    /// The client carries the caller's identity for the chain — the hash it
    /// routes connections by — and that keys the cache. The genesis hash
    /// placed in [`ChainState`], and therefore signed into every allowance
    /// extrinsic, is always the one the chain itself reports: a host whose
    /// configured constant has gone stale (a wiped testnet) still produces
    /// valid extrinsics. A divergence is logged, since it means the host's
    /// chain configuration needs refreshing — see RFC-0026, which lets hosts
    /// discover these hashes instead of hard-coding them.
    ///
    /// An entry is reused only when both the spec version **and** the reported
    /// genesis hash still match. Spec version alone cannot see a chain that was
    /// wiped and redeployed from the same runtime, which keeps its spec version
    /// and gets a new genesis; an entry held across that would sign
    /// `CheckGenesis` for a chain that no longer exists. Both reads are issued
    /// together, so validating on the pair costs no extra round trip.
    pub async fn get(&self, client: &ChainClient) -> Result<ChainContext, StatementAllowanceError> {
        let rpc = client.rpc();
        let configured_genesis_hash = client.configured_genesis_hash;
        let ((spec_version, transaction_version), genesis_hash) =
            futures::try_join!(fetch_runtime_version(rpc), fetch_genesis_hash(rpc))?;
        if let Some(cached) = self.cached(configured_genesis_hash, spec_version, genesis_hash) {
            return Ok(cached);
        }

        let _download = self.downloads.lock().await;
        // Another caller may have finished the download while this one waited.
        if let Some(cached) = self.cached(configured_genesis_hash, spec_version, genesis_hash) {
            return Ok(cached);
        }
        if genesis_hash != configured_genesis_hash {
            warn!(
                configured = %hex::encode(configured_genesis_hash),
                reported = %hex::encode(genesis_hash),
                "chain reports a different genesis than the host configured; using the chain's"
            );
        }
        let context = ChainContext {
            metadata: Arc::new(fetch_metadata(rpc).await?),
            state: ChainState {
                spec_version,
                transaction_version,
                genesis_hash,
                nonce: 0,
            },
        };
        self.entries
            .lock()
            .expect("chain context cache mutex poisoned")
            .insert(configured_genesis_hash, context.clone());
        Ok(context)
    }

    fn cached(
        &self,
        configured_genesis_hash: [u8; 32],
        spec_version: u32,
        genesis_hash: [u8; 32],
    ) -> Option<ChainContext> {
        self.entries
            .lock()
            .expect("chain context cache mutex poisoned")
            .get(&configured_genesis_hash)
            .filter(|cached| {
                cached.state.spec_version == spec_version
                    && cached.state.genesis_hash == genesis_hash
            })
            .cloned()
    }
}

/// Read a u32 field from a JSON object.
fn json_u32(value: &Value, field: &'static str) -> Result<u32, StatementAllowanceError> {
    value
        .get(field)
        .and_then(Value::as_u64)
        .and_then(|v| u32::try_from(v).ok())
        .ok_or_else(|| ChainStateError::MissingU32Field { field }.into())
}

/// Result of a statement-store allowance registration attempt.
#[derive(Debug)]
pub enum RegistrationOutcome {
    /// The extrinsic reached a block and the slot entry was verified at that
    /// block: the target now holds slot `seq`.
    Registered {
        /// Block hash the extrinsic landed in.
        block_hash: String,
        /// Claimed slot sequence.
        seq: u32,
        /// Ring index the proof was built against.
        ring_index: u32,
    },
    /// The target already held a slot this period; nothing submitted.
    AlreadyAllocated {
        /// Existing slot sequence.
        seq: u32,
    },
}

/// Target and slot-selection inputs for one statement-store registration.
pub struct RegistrationParams<'a> {
    /// Account that should receive the statement-store registration.
    pub target: &'a [u8; 32],
    /// Statement-store period for which the registration is requested.
    pub period: u32,
    /// Ring parameters used to build the membership proof.
    pub ring: &'a RingParams,
    /// Whether an existing registration for this period may be reused.
    pub reuse_existing: bool,
    /// A free slot the caller's own scan already selected, used for the first
    /// attempt so the scan is not repeated. The duplicate-submit retry rescans,
    /// so this only ever shortcuts the first submission.
    pub preselected: Option<u32>,
}

/// Result of a long-term storage claim attempt.
pub enum LongTermStorageOutcome {
    /// The extrinsic reached a block; the target should receive Bulletin
    /// authorization once XCM/chain propagation completes.
    Claimed {
        /// Block hash the extrinsic landed in.
        block_hash: String,
        /// Claimed counter within the long-term storage period.
        counter: u8,
        /// Ring index the proof was built against.
        ring_index: u32,
    },
}

/// Bulletin authorization state for one account.
#[derive(Debug, Clone, Copy)]
pub struct BulletinAllowanceInfo {
    /// Number of preimage bytes that remain available.
    pub remained_size: u64,
    /// Number of preimage submissions that remain available.
    pub remained_transactions: u32,
    /// Block at which the allowance expires.
    pub expires_in: u32,
    /// Block at which this allowance snapshot was fetched.
    pub fetched_at: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Encode, Decode)]
enum BulletinAuthorizationScope {
    Account([u8; 32]),
}

impl BulletinAllowanceInfo {
    /// Returns whether the snapshot still permits at least one submission.
    pub fn available(self) -> bool {
        self.remained_size > 0
            && self.remained_transactions > 0
            && self.fetched_at < self.expires_in
    }
}

/// Find the newest ring (scanning up to `lookback` back from the current index)
/// that includes our member key. Reads the ring exponent once and stops at the
/// first match. Every read is pinned to one finalized block so the snapshot is
/// internally consistent; the pinned hash is recorded on the returned
/// [`RingParams`].
pub async fn find_including_ring(
    rpc: &RpcClient,
    metadata: &Metadata,
    entropy: [u8; 32],
    lookback: u32,
) -> Result<Option<RingParams>, StatementAllowanceError> {
    let member = proof::member_key(entropy);
    let at = rpc.finalized_head().await?;
    let exponent = ring::read_ring_exponent(rpc, metadata, &at).await?;
    let current = ring::read_current_ring_index_at(rpc, &at).await?;
    let oldest = current.saturating_sub(lookback);
    for ring_index in (oldest..=current).rev() {
        let members = ring::read_ring_members_at(rpc, ring_index, &at).await?;
        if members.contains(&member) {
            return Ok(Some(RingParams {
                members,
                exponent,
                ring_index,
                block_hash: at,
            }));
        }
    }
    Ok(None)
}

/// Register statement-store allowance for `target`, proving membership in the
/// already-located `ring`, at UTC-day `period`.
pub async fn register_statement_account(
    rpc: &RpcClient,
    metadata: &Metadata,
    chain_state: &ChainState,
    entropy: [u8; 32],
    params: RegistrationParams<'_>,
) -> Result<RegistrationOutcome, StatementAllowanceError> {
    let mut skipped_duplicate_slots = Vec::new();
    let mut preselected = params.preselected;
    loop {
        let seq = match preselected.take() {
            Some(seq) => seq,
            None => match slot::scan_slot_excluding(
                rpc,
                metadata,
                entropy,
                params.period,
                params.target,
                &skipped_duplicate_slots,
                params.reuse_existing,
            )
            .await?
            {
                SlotSelection::AlreadyAllocated(seq) => {
                    return Ok(RegistrationOutcome::AlreadyAllocated { seq });
                }
                SlotSelection::Free(seq) => seq,
                SlotSelection::Full { max } => {
                    return Err(SlotError::NoFreeStatementStoreSlot {
                        period: params.period,
                        max,
                    }
                    .into());
                }
            },
        };

        let context = slot::derive_slot_context(params.period, seq);
        let call = extrinsic::build_set_statement_store_account_call(
            metadata,
            params.period,
            seq,
            params.target,
        )?;
        let message = extension::build_proof_message(metadata, &call, chain_state)?;
        let domain = proof::domain_for_ring_exponent(params.ring.exponent)?;
        let ring_proof =
            proof::ring_vrf_proof(domain, entropy, &params.ring.members, &context, &message)?;
        let as_resources_extra =
            extrinsic::build_as_resources_extra(metadata, &ring_proof, params.ring.ring_index)?;
        let extrinsic =
            extrinsic::build_unsigned_extrinsic(metadata, chain_state, &call, &as_resources_extra)?;

        match rpc.submit_and_watch(&extrinsic).await {
            Ok(block_hash) => {
                if slot::read_slot_account_at(rpc, entropy, params.period, seq, &block_hash).await?
                    != Some(*params.target)
                {
                    return Err(SlotError::RegistrationVerificationMismatch {
                        block_hash,
                        period: params.period,
                        seq,
                    }
                    .into());
                }
                return Ok(RegistrationOutcome::Registered {
                    block_hash,
                    seq,
                    ring_index: params.ring.ring_index,
                });
            }
            Err(err) if duplicate_submit_error(&err.to_string()) => {
                skipped_duplicate_slots.push(seq);
            }
            Err(err) => return Err(err),
        }
    }
}

/// Claim long-term Bulletin storage authorization for `target`, proving
/// membership in the already-located `ring`, at People-chain `period`.
pub async fn claim_long_term_storage(
    rpc: &RpcClient,
    metadata: &Metadata,
    chain_state: &ChainState,
    entropy: [u8; 32],
    target: &[u8; 32],
    period: u32,
    ring: &RingParams,
) -> Result<LongTermStorageOutcome, StatementAllowanceError> {
    let revision =
        ring::read_ring_revision(rpc, metadata, ring.ring_index, &ring.block_hash).await?;
    let mut skipped_duplicate_counters = Vec::new();
    loop {
        let counter = slot::scan_long_term_storage_counter_excluding(
            rpc,
            metadata,
            entropy,
            period,
            &skipped_duplicate_counters,
        )
        .await?;

        let context = slot::derive_long_term_storage_context(period, counter);
        let call =
            extrinsic::build_claim_long_term_storage_call(metadata, period, counter, target)?;
        let message = extension::build_proof_message(metadata, &call, chain_state)?;
        let domain = proof::domain_for_ring_exponent(ring.exponent)?;
        let ring_proof = proof::ring_vrf_proof(domain, entropy, &ring.members, &context, &message)?;
        let as_resources_extra = extrinsic::build_long_term_storage_extra(
            metadata,
            &ring_proof,
            ring.ring_index,
            revision,
        )?;
        let extrinsic =
            extrinsic::build_unsigned_extrinsic(metadata, chain_state, &call, &as_resources_extra)?;
        debug!(
            period,
            counter,
            ring_index = ring.ring_index,
            revision,
            "submitting Bulletin long-term-storage claim"
        );

        match rpc.submit_and_watch(&extrinsic).await {
            Ok(block_hash) => {
                return Ok(LongTermStorageOutcome::Claimed {
                    block_hash,
                    counter,
                    ring_index: ring.ring_index,
                });
            }
            Err(err) if duplicate_submit_error(&err.to_string()) => {
                skipped_duplicate_counters.push(counter);
            }
            Err(err) => {
                warn!(
                    period,
                    counter,
                    ring_index = ring.ring_index,
                    revision,
                    %err,
                    "Bulletin long-term-storage claim failed"
                );
                return Err(err);
            }
        }
    }
}

/// Fetch Bulletin `TransactionStorage.Authorizations[Account(target)]`.
pub async fn fetch_bulletin_allowance(
    rpc: &RpcClient,
    target: &[u8; 32],
) -> Result<Option<BulletinAllowanceInfo>, StatementAllowanceError> {
    let Some(bytes) = rpc.get_storage(&bulletin_authorization_key(target)).await? else {
        return Ok(None);
    };
    let fetched_at = fetch_block_number(rpc).await?;
    decode_bulletin_allowance(&bytes, fetched_at).map(Some)
}

/// Wait until Bulletin authorization is available and fresher than `current`.
pub async fn wait_bulletin_authorization(
    rpc: &RpcClient,
    target: &[u8; 32],
    current: Option<BulletinAllowanceInfo>,
    timeout: Duration,
) -> Result<BulletinAllowanceInfo, StatementAllowanceError> {
    let started = Instant::now();
    let baseline = current.filter(|info| info.available());
    loop {
        let Some(info) = fetch_bulletin_allowance(rpc, target).await? else {
            wait_before_next_bulletin_authorization_poll(started, timeout).await?;
            continue;
        };
        if authorization_refreshed(info, baseline) {
            return Ok(info);
        }
        wait_before_next_bulletin_authorization_poll(started, timeout).await?;
    }
}

async fn wait_before_next_bulletin_authorization_poll(
    started: Instant,
    timeout: Duration,
) -> Result<(), StatementAllowanceError> {
    let Some(remaining) = timeout.checked_sub(started.elapsed()) else {
        return Err(StatementAllowanceError::BulletinAuthorizationTimeout);
    };
    let delay = futures_timer::Delay::new(remaining.min(Duration::from_secs(2))).fuse();
    futures::pin_mut!(delay);
    delay.await;
    Ok(())
}

fn authorization_refreshed(
    info: BulletinAllowanceInfo,
    baseline: Option<BulletinAllowanceInfo>,
) -> bool {
    if !info.available() {
        return false;
    }
    match baseline {
        None => true,
        Some(current) => {
            info.remained_transactions > current.remained_transactions
                || info.remained_size > current.remained_size
                || info.expires_in > current.expires_in
        }
    }
}

/// `TransactionStorage.Authorizations[AuthorizationScope::Account(target)]`.
fn bulletin_authorization_key(target: &[u8; 32]) -> Vec<u8> {
    let scope = BulletinAuthorizationScope::Account(*target).encode();
    [
        twox_128(b"TransactionStorage").as_slice(),
        twox_128(b"Authorizations").as_slice(),
        &ring::blake2_128_concat(&scope),
    ]
    .concat()
}

fn decode_bulletin_allowance(
    bytes: &[u8],
    fetched_at: u32,
) -> Result<BulletinAllowanceInfo, StatementAllowanceError> {
    let mut input = bytes;
    let transactions =
        u32::decode(&mut input).map_err(|err| ChainStateError::AuthorizationFieldDecode {
            field: "transactions",
            source: err,
        })?;
    let transactions_allowance =
        u32::decode(&mut input).map_err(|err| ChainStateError::AuthorizationFieldDecode {
            field: "transactions_allowance",
            source: err,
        })?;
    let bytes_used =
        u64::decode(&mut input).map_err(|err| ChainStateError::AuthorizationFieldDecode {
            field: "bytes",
            source: err,
        })?;
    let _bytes_permanent =
        u64::decode(&mut input).map_err(|err| ChainStateError::AuthorizationFieldDecode {
            field: "bytes_permanent",
            source: err,
        })?;
    let bytes_allowance =
        u64::decode(&mut input).map_err(|err| ChainStateError::AuthorizationFieldDecode {
            field: "bytes_allowance",
            source: err,
        })?;
    let expires_in =
        u32::decode(&mut input).map_err(|err| ChainStateError::AuthorizationFieldDecode {
            field: "expiration",
            source: err,
        })?;
    Ok(BulletinAllowanceInfo {
        remained_size: bytes_allowance.saturating_sub(bytes_used),
        remained_transactions: transactions_allowance.saturating_sub(transactions),
        expires_in,
        fetched_at,
    })
}

async fn fetch_block_number(rpc: &RpcClient) -> Result<u32, StatementAllowanceError> {
    let header = rpc.call("chain_getHeader", json!([])).await?;
    let number = header
        .get("number")
        .and_then(Value::as_str)
        .ok_or(ChainStateError::HeaderNumberMissing)?;
    u32::from_str_radix(number.trim_start_matches("0x"), 16)
        .map_err(|err| ChainStateError::HeaderNumberParse(err).into())
}

/// Pool responses meaning an equivalent claim already occupies the pool, so
/// the scan should move to the next slot. Bans and validity failures are hard
/// errors for the caller.
fn duplicate_submit_error(message: &str) -> bool {
    let message = message.to_ascii_lowercase();
    message.contains("priority is too low") || message.contains("already imported")
}

#[cfg(test)]
mod tests {
    use subxt_rpcs::RpcClient as HostRpcClient;

    use super::rpc::testing::ScriptedRpc;
    use super::*;

    /// Fixture metadata captured from paseo-next-v2 (raw `RuntimeMetadataPrefixed`).
    const FIXTURE: &[u8] = include_bytes!("../../tests/fixtures/paseo-next-v2-metadata.scale");

    fn allowance(
        remained_size: u64,
        remained_transactions: u32,
        expires_in: u32,
    ) -> BulletinAllowanceInfo {
        BulletinAllowanceInfo {
            remained_size,
            remained_transactions,
            expires_in,
            fetched_at: 10,
        }
    }

    #[test]
    fn bulletin_refresh_accepts_available_state_when_baseline_was_unusable() {
        let exhausted_by_size = allowance(0, 4, 100);
        let refreshed_same_transactions = allowance(4096, 4, 100);

        assert!(!exhausted_by_size.available());
        assert!(authorization_refreshed(
            refreshed_same_transactions,
            Some(exhausted_by_size).filter(|info| info.available()),
        ));
    }

    #[test]
    fn bulletin_refresh_accepts_size_only_increase() {
        let baseline = allowance(128, 4, 100);
        let refreshed = allowance(4096, 4, 100);

        assert!(authorization_refreshed(refreshed, Some(baseline)));
    }

    #[test]
    fn bulletin_refresh_rejects_unchanged_available_state() {
        let baseline = allowance(128, 4, 100);

        assert!(!authorization_refreshed(baseline, Some(baseline)));
    }

    #[test]
    fn banned_submissions_are_not_classified_as_duplicates() {
        let classified: Vec<bool> = [
            "Priority is too low: (100 vs 100)",
            "Transaction Already Imported",
            "Transaction is temporarily banned",
            "Invalid Transaction",
        ]
        .into_iter()
        .map(duplicate_submit_error)
        .collect();

        assert_eq!(classified, vec![true, true, false, false]);
    }

    #[test]
    fn bulletin_account_scope_matches_runtime_enum_codec() {
        let scope = BulletinAuthorizationScope::Account([0x42; 32]);
        let encoded = scope.encode();

        assert_eq!(encoded, [vec![0x00], vec![0x42; 32]].concat());
        assert_eq!(
            BulletinAuthorizationScope::decode(&mut encoded.as_slice()).unwrap(),
            scope
        );
    }

    /// A `state_getRuntimeVersion` result for `spec_version`.
    fn runtime_version(spec_version: u32) -> String {
        format!(r#"{{"specVersion":{spec_version},"transactionVersion":1}}"#)
    }

    /// The fixture metadata as a `state_getMetadata` hex result.
    fn metadata_result() -> String {
        format!(r#""0x{}""#, hex::encode(FIXTURE))
    }

    /// A `chain_getBlockHash(0)` result for `genesis_hash`.
    fn genesis_result(genesis_hash: [u8; 32]) -> String {
        format!(r#""0x{}""#, hex::encode(genesis_hash))
    }

    /// Method names the scripted transport saw, in order.
    fn methods(scripted: &ScriptedRpc) -> Vec<String> {
        scripted
            .calls()
            .into_iter()
            .map(|(method, _)| method)
            .collect()
    }

    /// The requests one cache miss makes, in order. The two validation reads
    /// are issued together, so both happen whether or not the entry is reused.
    const MISS: [&str; 3] = [
        "state_getRuntimeVersion",
        "chain_getBlockHash",
        "state_getMetadata",
    ];
    /// The requests one cache hit makes: validation only, no metadata download.
    const HIT: [&str; 2] = ["state_getRuntimeVersion", "chain_getBlockHash"];

    /// One call's worth of scripted responses: the two validation reads plus,
    /// when the entry has to be built, the metadata download.
    fn call_script(spec_version: u32, reported: [u8; 32], downloads: bool) -> Vec<String> {
        let mut script = vec![runtime_version(spec_version), genesis_result(reported)];
        if downloads {
            script.push(metadata_result());
        }
        script
    }

    /// Drive `ChainContextCache::get` over `responses`, fetching each entry in
    /// `chains` in turn, and report the methods the transport saw.
    fn scripted_cache_run(responses: &[String], chains: &[[u8; 32]]) -> Vec<String> {
        let scripted = ScriptedRpc::new(responses.iter().map(String::as_str));
        let cache = ChainContextCache::default();

        futures::executor::block_on(async {
            for genesis_hash in chains {
                let client = ChainClient::new(
                    RpcClient::new(HostRpcClient::new(scripted.clone())),
                    *genesis_hash,
                );
                cache
                    .get(&client)
                    .await
                    .expect("scripted chain context fetch succeeds");
            }
        });
        methods(&scripted)
    }

    /// Transport that answers by method rather than in order, and yields inside
    /// every request so concurrent cache misses genuinely interleave. Counts the
    /// metadata downloads, which is the cost the cache exists to avoid.
    #[derive(Clone, Default)]
    struct CountingRpc(std::sync::Arc<CountingState>);

    #[derive(Default)]
    struct CountingState {
        metadata_downloads: std::sync::atomic::AtomicUsize,
    }

    impl CountingRpc {
        fn metadata_downloads(&self) -> usize {
            self.0
                .metadata_downloads
                .load(std::sync::atomic::Ordering::Relaxed)
        }
    }

    impl subxt_rpcs::client::RpcClientT for CountingRpc {
        fn request_raw<'a>(
            &'a self,
            method: &'a str,
            _params: Option<Box<subxt_rpcs::client::RawValue>>,
        ) -> subxt_rpcs::client::RawRpcFuture<'a, Box<subxt_rpcs::client::RawValue>> {
            let body = match method {
                "state_getRuntimeVersion" => runtime_version(1_000_000),
                "chain_getBlockHash" => genesis_result([0xaa; 32]),
                "state_getMetadata" => {
                    self.0
                        .metadata_downloads
                        .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                    metadata_result()
                }
                other => panic!("unexpected request `{other}`"),
            };
            Box::pin(async move {
                // Yield so a concurrently polled caller reaches the same point.
                let mut yielded = false;
                futures::future::poll_fn(move |cx| {
                    if yielded {
                        core::task::Poll::Ready(())
                    } else {
                        yielded = true;
                        cx.waker().wake_by_ref();
                        core::task::Poll::Pending
                    }
                })
                .await;
                Ok(subxt_rpcs::client::RawValue::from_string(body)
                    .expect("scripted response is valid JSON"))
            })
        }

        fn subscribe_raw<'a>(
            &'a self,
            _sub: &'a str,
            _params: Option<Box<subxt_rpcs::client::RawValue>>,
            _unsub: &'a str,
        ) -> subxt_rpcs::client::RawRpcFuture<'a, subxt_rpcs::client::RawRpcSubscription> {
            unreachable!("the chain context cache does not subscribe")
        }
    }

    #[test]
    fn concurrent_misses_download_the_metadata_once() {
        let counting = CountingRpc::default();
        let client = ChainClient::new(
            RpcClient::new(HostRpcClient::new(counting.clone())),
            [0xaa; 32],
        );
        let cache = ChainContextCache::default();

        futures::executor::block_on(async {
            let (first, second) = futures::join!(cache.get(&client), cache.get(&client));
            let first = first.expect("first read");
            let second = second.expect("second read");
            // Both callers end up on the same entry.
            assert!(Arc::ptr_eq(&first.metadata, &second.metadata));
        });

        assert_eq!(counting.metadata_downloads(), 1);
    }

    #[test]
    fn a_chain_is_read_once_per_spec_version() {
        let seen = scripted_cache_run(
            &[
                call_script(1_000_000, [0xaa; 32], true),
                call_script(1_000_000, [0xaa; 32], false),
            ]
            .concat(),
            &[[0xaa; 32], [0xaa; 32]],
        );

        assert_eq!(seen, [MISS.as_slice(), HIT.as_slice()].concat());
    }

    #[test]
    fn a_wipe_that_keeps_the_spec_version_refreshes_the_entry() {
        // A chain redeployed from the same runtime keeps its spec version and
        // gets a new genesis. Validating on the spec version alone would reuse
        // the entry and sign `CheckGenesis` for the chain that no longer exists.
        let seen = scripted_cache_run(
            &[
                call_script(1_000_000, [0xaa; 32], true),
                call_script(1_000_000, [0xcc; 32], true),
            ]
            .concat(),
            &[[0xaa; 32], [0xaa; 32]],
        );

        assert_eq!(seen, [MISS, MISS].concat());
    }

    #[test]
    fn a_wipe_is_reflected_in_the_signed_genesis_hash() {
        let responses = [
            call_script(1_000_000, [0xaa; 32], true),
            call_script(1_000_000, [0xcc; 32], true),
        ]
        .concat();
        let scripted = ScriptedRpc::new(responses.iter().map(String::as_str));
        let client = ChainClient::new(RpcClient::new(HostRpcClient::new(scripted)), [0xaa; 32]);
        let cache = ChainContextCache::default();

        futures::executor::block_on(async {
            let before = cache.get(&client).await.expect("first read");
            assert_eq!(before.state.genesis_hash, [0xaa; 32]);

            let after = cache.get(&client).await.expect("read after a wipe");
            assert_eq!(after.state.genesis_hash, [0xcc; 32]);
        });
    }

    #[test]
    fn a_spec_version_bump_refreshes_the_entry() {
        let seen = scripted_cache_run(
            &[
                call_script(1_000_000, [0xaa; 32], true),
                call_script(1_000_001, [0xaa; 32], true),
            ]
            .concat(),
            &[[0xaa; 32], [0xaa; 32]],
        );

        assert_eq!(seen, [MISS, MISS].concat());
    }

    #[test]
    fn chains_do_not_share_a_cache_entry() {
        let seen = scripted_cache_run(
            &[
                call_script(1_000_000, [0xaa; 32], true),
                call_script(1_000_000, [0xbb; 32], true),
            ]
            .concat(),
            &[[0xaa; 32], [0xbb; 32]],
        );

        assert_eq!(seen, [MISS, MISS].concat());
    }

    #[test]
    fn a_stale_configured_genesis_still_yields_the_chains_own_hash() {
        let responses = call_script(1_000_000, [0xbb; 32], true);
        let scripted = ScriptedRpc::new(responses.iter().map(String::as_str));
        let client = ChainClient::new(RpcClient::new(HostRpcClient::new(scripted)), [0xaa; 32]);
        let cache = ChainContextCache::default();

        let context = futures::executor::block_on(cache.get(&client))
            .expect("a stale configured genesis is not fatal");

        // `CheckGenesis` is signed over this, so it must be the chain's value,
        // not the caller's possibly-stale constant.
        assert_eq!(context.state.genesis_hash, [0xbb; 32]);
    }

    #[test]
    fn a_stale_configured_genesis_still_keys_the_cache() {
        let seen = scripted_cache_run(
            &[
                call_script(1_000_000, [0xbb; 32], true),
                call_script(1_000_000, [0xbb; 32], false),
            ]
            .concat(),
            &[[0xaa; 32], [0xaa; 32]],
        );

        assert_eq!(seen, [MISS.as_slice(), HIT.as_slice()].concat());
    }

    /// `StmtStoreAllowanceEntry { account_id, seq: 0, since: 0 }` as a scripted
    /// JSON storage result.
    fn slot_entry(account: [u8; 32]) -> String {
        let entry = (account, 0u32, 0u64).encode();
        format!(r#""0x{}""#, hex::encode(entry))
    }

    /// Run `register_statement_account` against a scripted chain: all ten
    /// slots free, the extrinsic reaches block `0xb10c`, and the verification
    /// read at that block returns `verified_entry`.
    fn scripted_registration(
        verified_entry: &str,
    ) -> (
        Result<RegistrationOutcome, StatementAllowanceError>,
        ScriptedRpc,
    ) {
        scripted_registration_with(verified_entry, None, 10)
    }

    /// Run `register_statement_account` against a scripted chain: `free_slots`
    /// slots answered as free, the extrinsic reaching block `0xb10c`, and the
    /// verification read at that block returning `verified_entry`.
    fn scripted_registration_with(
        verified_entry: &str,
        preselected: Option<u32>,
        free_slots: usize,
    ) -> (
        Result<RegistrationOutcome, StatementAllowanceError>,
        ScriptedRpc,
    ) {
        let metadata = Metadata::decode(FIXTURE).unwrap();
        let chain_state = ChainState {
            spec_version: 1_000_000,
            transaction_version: 1,
            genesis_hash: [0xab; 32],
            nonce: 0,
        };
        let entropy = [0x11; 32];
        let ring = RingParams {
            members: vec![proof::member_key(entropy)],
            exponent: 9,
            ring_index: 0,
            block_hash: "0xfinal".to_string(),
        };

        let mut responses = vec!["null"; free_slots];
        responses.push(verified_entry);
        let scripted = ScriptedRpc::new(responses);
        scripted.script_subscription([r#"{"inBlock":"0xb10c"}"#]);
        let rpc = RpcClient::new(HostRpcClient::new(scripted.clone()));

        let outcome = futures::executor::block_on(register_statement_account(
            &rpc,
            &metadata,
            &chain_state,
            entropy,
            RegistrationParams {
                target: &[0x22; 32],
                period: 7,
                ring: &ring,
                reuse_existing: true,
                preselected,
            },
        ));
        (outcome, scripted)
    }

    /// Storage reads the scripted transport served.
    fn storage_reads(scripted: &ScriptedRpc) -> usize {
        scripted
            .calls()
            .iter()
            .filter(|(method, _)| method == "state_getStorage")
            .count()
    }

    #[test]
    fn registration_is_verified_at_the_included_block() {
        let (outcome, scripted) = scripted_registration(&slot_entry([0x22; 32]));

        assert!(matches!(
            outcome.unwrap(),
            RegistrationOutcome::Registered { block_hash, seq: 0, ring_index: 0 }
                if block_hash == "0xb10c"
        ));
        let (method, params) = scripted.calls().last().cloned().unwrap();
        assert_eq!(method, "state_getStorage");
        assert!(
            params.ends_with(r#","0xb10c"]"#),
            "verification read not pinned to the included block: {params}"
        );
    }

    #[test]
    fn a_preselected_slot_is_not_rescanned() {
        // No slots are scripted as free: if the caller's selection were ignored
        // and the slots rescanned, the scripted transport would run dry.
        let (outcome, scripted) = scripted_registration_with(&slot_entry([0x22; 32]), Some(0), 0);

        assert!(matches!(
            outcome.unwrap(),
            RegistrationOutcome::Registered { seq: 0, .. }
        ));
        // The verification read at the included block, and nothing else.
        assert_eq!(storage_reads(&scripted), 1);
    }

    #[test]
    fn a_scan_without_a_preselection_reads_every_slot() {
        let (outcome, scripted) = scripted_registration(&slot_entry([0x22; 32]));

        assert!(outcome.is_ok());
        // Ten slots scanned plus the verification read.
        assert_eq!(storage_reads(&scripted), 11);
    }

    #[test]
    fn registration_fails_when_the_included_block_lacks_the_slot() {
        let (outcome, _scripted) = scripted_registration(&slot_entry([0x99; 32]));

        let err = outcome.unwrap_err();
        assert!(
            err.to_string().contains("0xb10c"),
            "unexpected error: {err}"
        );
    }
}
