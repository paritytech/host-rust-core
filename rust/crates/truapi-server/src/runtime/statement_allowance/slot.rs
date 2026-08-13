//! StatementStore allowance slot selection.
//!
//! An allowance is claimed at `(period, seq)`. The slot is bound to a 32-byte
//! `SSS_SLOT` context; occupancy is read from
//! `Resources.StatementStoreAllowances[period][alias]`, where the alias is
//! derived from OUR bandersnatch entropy in that slot context. Mirrors
//! signing-bot `allowance.ts` / `allowance-slots.ts`.

use parity_scale_codec::{Decode, Encode};
use sp_crypto_hashing::twox_128;
use thiserror::Error;
use verifiable::Error as VerifiableError;
use verifiable::GenerateVerifiable;
use verifiable::ring::bandersnatch::BandersnatchVrfVerifiable;

use super::StatementAllowanceError;
use super::extension::{Metadata, MetadataError};
use super::ring::blake2_128_concat;
use super::rpc::RpcClient;

/// StatementStore allowance period: one UTC day, in seconds.
pub const STATEMENT_STORE_PERIOD_SECONDS: u64 = 86_400;
/// Bulletin long-term-storage claim context prefix.
const LONG_TERM_STORAGE_CONTEXT_PREFIX: &[u8] = b"pop:polkadot.net/rsc-lts";

/// Error while deriving aliases or selecting allowance slots.
#[derive(Debug, Error)]
pub enum SlotError {
    /// Long-term storage period duration constant was zero.
    #[error("Resources.LongTermStoragePeriodDuration is zero")]
    LongTermStoragePeriodDurationZero,
    /// Bandersnatch alias derivation failed.
    #[error("{context} alias_in_context failed: {error:?}")]
    AliasInContext {
        /// Alias context name.
        context: &'static str,
        /// Alias derivation failure.
        error: VerifiableError,
    },
    /// No free statement-store slot was found.
    #[error("no free StatementStore slot in period {period} (max {max})")]
    NoFreeStatementStoreSlot {
        /// Period scanned.
        period: u32,
        /// Maximum slot count.
        max: u32,
    },
    /// No free long-term-storage slot was found.
    #[error("no free long-term-storage slot in period {period} (max {max})")]
    NoFreeLongTermStorageSlot {
        /// Period scanned.
        period: u32,
        /// Maximum slot count.
        max: u8,
    },
    /// Free slots exist but all were excluded by this call's own submissions.
    #[error(
        "every free StatementStore slot in period {period} is awaiting one of this call's own submissions"
    )]
    FreeSlotsAwaitingSubmission {
        /// Period scanned.
        period: u32,
    },
    /// `Timestamp.Now` was absent or undecodable, so slot ages cannot be judged.
    #[error("Timestamp.Now missing from chain state")]
    MissingChainTimestamp,
    /// Registration reached a block but the slot was not held by the target.
    #[error(
        "registration reached block {block_hash} but slot (period {period}, seq {seq}) is not held by the target account"
    )]
    RegistrationVerificationMismatch {
        /// Block hash the registration reached.
        block_hash: String,
        /// Registration period.
        period: u32,
        /// Slot sequence.
        seq: u32,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Encode, Decode)]
struct StatementStoreAllowanceEntry {
    account_id: [u8; 32],
    seq: u32,
    since: u64,
}

/// A slot that is occupied, as observed by a scan.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct OccupiedSlot {
    /// Slot index within the period.
    pub seq: u32,
    /// Account the slot currently allows.
    pub account_id: [u8; 32],
    /// Unix seconds at which the slot was last set.
    pub since: u64,
}

/// The current allowance period for `now_seconds`.
pub fn current_period(now_seconds: u64) -> u32 {
    (now_seconds / STATEMENT_STORE_PERIOD_SECONDS) as u32
}

/// The current long-term-storage period for `now_seconds`.
pub fn current_long_term_storage_period(
    now_seconds: u64,
    period_duration: u32,
) -> Result<u32, StatementAllowanceError> {
    if period_duration == 0 {
        return Err(SlotError::LongTermStoragePeriodDurationZero.into());
    }
    Ok((now_seconds / u64::from(period_duration)) as u32)
}

/// Derive the 32-byte StatementStore slot context:
/// `"SSS_SLOT:" ‖ u32be(period) ‖ u32be(seq) ‖ 0x20 fill`.
pub fn derive_slot_context(period: u32, seq: u32) -> [u8; 32] {
    let mut ctx = [0x20u8; 32];
    ctx[..9].copy_from_slice(b"SSS_SLOT:");
    ctx[9..13].copy_from_slice(&period.to_be_bytes());
    ctx[13..17].copy_from_slice(&seq.to_be_bytes());
    ctx
}

/// Derive the 32-byte Bulletin long-term-storage slot context:
/// `"pop:polkadot.net/rsc-lts" ‖ u32be(period) ‖ counter ‖ zero fill`.
pub fn derive_long_term_storage_context(period: u32, counter: u8) -> [u8; 32] {
    let mut ctx = [0u8; 32];
    ctx[..LONG_TERM_STORAGE_CONTEXT_PREFIX.len()].copy_from_slice(LONG_TERM_STORAGE_CONTEXT_PREFIX);
    let offset = LONG_TERM_STORAGE_CONTEXT_PREFIX.len();
    ctx[offset..offset + 4].copy_from_slice(&period.to_be_bytes());
    ctx[offset + 4] = counter;
    ctx
}

/// The slot alias for our `entropy` at `(period, seq)`.
pub fn slot_alias(
    entropy: [u8; 32],
    period: u32,
    seq: u32,
) -> Result<[u8; 32], StatementAllowanceError> {
    let secret = BandersnatchVrfVerifiable::new_secret(entropy);
    let context = derive_slot_context(period, seq);
    BandersnatchVrfVerifiable::alias_in_context(&secret, &context).map_err(|err| {
        SlotError::AliasInContext {
            context: "statement-store slot",
            error: err,
        }
        .into()
    })
}

/// The long-term-storage slot alias for our `entropy` at `(period, counter)`.
pub fn long_term_storage_alias(
    entropy: [u8; 32],
    period: u32,
    counter: u8,
) -> Result<[u8; 32], StatementAllowanceError> {
    let secret = BandersnatchVrfVerifiable::new_secret(entropy);
    let context = derive_long_term_storage_context(period, counter);
    BandersnatchVrfVerifiable::alias_in_context(&secret, &context).map_err(|err| {
        SlotError::AliasInContext {
            context: "long-term-storage slot",
            error: err,
        }
        .into()
    })
}

/// `Resources.StatementStoreAllowances[period][alias]` storage key.
/// key1 = Identity(u32be period); key2 = Blake2_128Concat(alias).
fn statement_store_allowance_key(period: u32, alias: &[u8; 32]) -> Vec<u8> {
    [
        twox_128(b"Resources").as_slice(),
        twox_128(b"StatementStoreAllowances").as_slice(),
        &period.to_be_bytes(),
        &blake2_128_concat(alias),
    ]
    .concat()
}

/// `Resources.SpentLongTermStorageAliases[period][alias]` storage key.
/// key1 = Identity(u32be period); key2 = Blake2_128Concat(alias).
fn spent_long_term_storage_alias_key(period: u32, alias: &[u8; 32]) -> Vec<u8> {
    [
        twox_128(b"Resources").as_slice(),
        twox_128(b"SpentLongTermStorageAliases").as_slice(),
        &period.to_be_bytes(),
        &blake2_128_concat(alias),
    ]
    .concat()
}

/// Max StatementStore slots per period from `Resources.LiteStmtStoreSlotsPerPeriod`.
fn max_slots(metadata: &Metadata) -> Result<u32, StatementAllowanceError> {
    let bytes = metadata
        .constant("Resources", "LiteStmtStoreSlotsPerPeriod")
        .ok_or(MetadataError::MissingConstant {
            pallet: "Resources",
            constant: "LiteStmtStoreSlotsPerPeriod",
        })?;
    let mut buf = [0u8; 4];
    let n = bytes.len().min(4);
    buf[..n].copy_from_slice(&bytes[..n]);
    Ok(u32::from_le_bytes(buf))
}

/// Max long-term-storage claims per period from
/// `Resources.LongTermStorageClaimsPerPeriod`.
fn long_term_storage_claims_per_period(metadata: &Metadata) -> Result<u8, StatementAllowanceError> {
    metadata
        .constant("Resources", "LongTermStorageClaimsPerPeriod")
        .and_then(|bytes| bytes.first().copied())
        .ok_or_else(|| {
            MetadataError::MissingConstant {
                pallet: "Resources",
                constant: "LongTermStorageClaimsPerPeriod",
            }
            .into()
        })
}

/// Long-term-storage period duration in seconds from
/// `Resources.LongTermStoragePeriodDuration`.
pub fn long_term_storage_period_duration(
    metadata: &Metadata,
) -> Result<u32, StatementAllowanceError> {
    let bytes = metadata
        .constant("Resources", "LongTermStoragePeriodDuration")
        .ok_or(MetadataError::MissingConstant {
            pallet: "Resources",
            constant: "LongTermStoragePeriodDuration",
        })?;
    let mut buf = [0u8; 4];
    let n = bytes.len().min(4);
    buf[..n].copy_from_slice(&bytes[..n]);
    Ok(u32::from_le_bytes(buf))
}

/// Decode a slot entry: `account_id(32) ‖ seq(u32 LE) ‖ since(u64 LE)`.
fn decode_entry(bytes: &[u8]) -> Option<StatementStoreAllowanceEntry> {
    StatementStoreAllowanceEntry::decode(&mut &bytes[..]).ok()
}

/// The slot to replace once no free slot is left: the oldest one that is not
/// the target's own and whose replacement cooldown has elapsed.
///
/// `chain_now_seconds` must come from the chain, not the host: `since` is a chain
/// timestamp and the runtime re-checks the cooldown against its own clock when it
/// validates the extrinsic. A host clock runs ahead of the chain by up to a block,
/// which would offer slots the runtime then refuses.
///
/// The comparison is strict because the runtime requires `now > since + cooldown`;
/// a slot at exactly the cooldown is still refused.
///
/// Takes the candidate list rather than scanning, so a caller can widen the
/// pool without changing this rule. Ties on `since` break to the lowest `seq`
/// so the choice is deterministic.
pub fn replaceable_slot(
    candidates: &[OccupiedSlot],
    target: &[u8; 32],
    chain_now_seconds: u64,
    cooldown_seconds: u64,
    excluded: &[u32],
) -> Option<u32> {
    candidates
        .iter()
        .filter(|slot| slot.account_id != *target)
        .filter(|slot| !excluded.contains(&slot.seq))
        .filter(|slot| chain_now_seconds.saturating_sub(slot.since) > cooldown_seconds)
        .min_by_key(|slot| (slot.since, slot.seq))
        .map(|slot| slot.seq)
}

/// `Timestamp.Now` storage key.
fn timestamp_now_key() -> Vec<u8> {
    [
        twox_128(b"Timestamp").as_slice(),
        twox_128(b"Now").as_slice(),
    ]
    .concat()
}

/// The chain's clock in unix seconds, decoded from `Timestamp.Now` milliseconds.
///
/// Slot ages are judged against this rather than the host clock, which runs up to
/// one block ahead of it.
pub async fn read_chain_now_seconds(rpc: &RpcClient) -> Result<u64, StatementAllowanceError> {
    let bytes = rpc
        .get_storage(&timestamp_now_key())
        .await?
        .ok_or(SlotError::MissingChainTimestamp)?;
    let millis = u64::decode(&mut &bytes[..]).map_err(|_| SlotError::MissingChainTimestamp)?;
    Ok(millis / 1_000)
}

/// Seconds an occupied slot must age before the runtime allows replacing it.
pub fn replacement_cooldown(metadata: &Metadata) -> Result<u64, StatementAllowanceError> {
    let bytes = metadata
        .constant("Resources", "StmtStoreReplacementCooldown")
        .ok_or(MetadataError::MissingConstant {
            pallet: "Resources",
            constant: "StmtStoreReplacementCooldown",
        })?;
    let mut buf = [0u8; 4];
    let n = bytes.len().min(4);
    buf[..n].copy_from_slice(&bytes[..n]);
    Ok(u64::from(u32::from_le_bytes(buf)))
}

/// The account holding our alias slot `(period, seq)`, read pinned to
/// `block_hash` (`None` when the slot entry is absent).
pub async fn read_slot_account_at(
    rpc: &RpcClient,
    entropy: [u8; 32],
    period: u32,
    seq: u32,
    block_hash: &str,
) -> Result<Option<[u8; 32]>, StatementAllowanceError> {
    let alias = slot_alias(entropy, period, seq)?;
    let key = statement_store_allowance_key(period, &alias);
    Ok(rpc
        .get_storage_at(&key, block_hash)
        .await?
        .and_then(|bytes| decode_entry(&bytes).map(|entry| entry.account_id)))
}

/// Outcome of scanning for a slot to register `target` in.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SlotSelection {
    /// A free `seq` we should claim.
    Free(u32),
    /// `target` already holds `seq` this period; no registration needed.
    AlreadyAllocated(u32),
    /// Every slot in the period is taken and none is reusable. Reported rather
    /// than raised so a caller can ask "is an allowance already in place" and
    /// get an answer instead of an error.
    Full {
        /// Slots the period has, for the caller's error.
        max: u32,
        /// Every occupied slot, so a caller can choose one to replace.
        occupied: Vec<OccupiedSlot>,
    },
    /// Slots are free but every one was excluded by this call's own earlier
    /// submissions. Distinct from [`SlotSelection::Full`]: replacing a live slot
    /// here would destroy capacity that is about to free up, because the
    /// excluded slots are only unavailable until those submissions resolve.
    FreeSlotsExcluded,
}

/// Scan slots `0..max` for `period`, returning the first non-excluded free seq
/// (or detecting that `target` already holds one). `entropy` is our
/// bandersnatch entropy.
pub async fn scan_slot_excluding(
    rpc: &RpcClient,
    metadata: &Metadata,
    entropy: [u8; 32],
    period: u32,
    target: &[u8; 32],
    excluded: &[u32],
    reuse_existing: bool,
) -> Result<SlotSelection, StatementAllowanceError> {
    let max = max_slots(metadata)?;
    let mut first_free: Option<u32> = None;
    let mut excluded_free = false;
    let mut occupied = Vec::new();
    for seq in 0..max {
        let alias = slot_alias(entropy, period, seq)?;
        let key = statement_store_allowance_key(period, &alias);
        match rpc.get_storage(&key).await? {
            None => {
                if excluded.contains(&seq) {
                    excluded_free = true;
                } else if first_free.is_none() {
                    first_free = Some(seq);
                }
            }
            Some(bytes) => {
                let Some(entry) = decode_entry(&bytes) else {
                    continue;
                };
                if reuse_existing && entry.account_id == *target {
                    return Ok(SlotSelection::AlreadyAllocated(seq));
                }
                occupied.push(OccupiedSlot {
                    seq,
                    account_id: entry.account_id,
                    since: entry.since,
                });
            }
        }
    }
    Ok(match (first_free, excluded_free) {
        (Some(seq), _) => SlotSelection::Free(seq),
        (None, true) => SlotSelection::FreeSlotsExcluded,
        (None, false) => SlotSelection::Full { max, occupied },
    })
}

/// Scan long-term-storage aliases `0..max` for `period`, returning the first
/// free counter not listed in `excluded`. `entropy` is our bandersnatch entropy.
pub async fn scan_long_term_storage_counter_excluding(
    rpc: &RpcClient,
    metadata: &Metadata,
    entropy: [u8; 32],
    period: u32,
    excluded: &[u8],
) -> Result<u8, StatementAllowanceError> {
    let max = long_term_storage_claims_per_period(metadata)?;
    for counter in 0..max {
        if excluded.contains(&counter) {
            continue;
        }
        let alias = long_term_storage_alias(entropy, period, counter)?;
        let key = spent_long_term_storage_alias_key(period, &alias);
        if rpc.get_storage(&key).await?.is_none() {
            return Ok(counter);
        }
    }
    Err(SlotError::NoFreeLongTermStorageSlot { period, max }.into())
}

#[cfg(test)]
mod tests {
    use subxt_rpcs::RpcClient as HostRpcClient;

    use super::super::rpc::testing::ScriptedRpc;
    use super::*;

    /// Fixture metadata captured from paseo-next-v2; its
    /// `LiteStmtStoreSlotsPerPeriod` is 10.
    const FIXTURE: &[u8] = include_bytes!("../../../tests/fixtures/paseo-next-v2-metadata.scale");
    const SLOTS: usize = 10;

    /// `StmtStoreAllowanceEntry { account_id, seq: 0, since: 0 }` as a scripted
    /// JSON storage result.
    fn slot_entry(account: [u8; 32]) -> String {
        entry_with_since(account, 0)
    }

    /// A scripted slot entry that was set at `since`.
    fn entry_with_since(account: [u8; 32], since: u64) -> String {
        format!(r#""0x{}""#, hex::encode((account, 0u32, since).encode()))
    }

    /// An occupied-slot candidate for the replacement rule.
    fn occupied(seq: u32, account_id: [u8; 32], since: u64) -> OccupiedSlot {
        OccupiedSlot {
            seq,
            account_id,
            since,
        }
    }

    /// Run `scan_slot_excluding` for `[0x22; 32]` against a scripted period
    /// whose slot occupancy is `slots`.
    fn scripted_find(slots: &[Option<[u8; 32]>]) -> SlotSelection {
        let metadata = Metadata::decode(FIXTURE).unwrap();
        let entries: Vec<String> = slots
            .iter()
            .map(|slot| slot.map_or_else(|| "null".to_string(), slot_entry))
            .collect();
        let scripted = ScriptedRpc::new(entries.iter().map(String::as_str));
        let rpc = RpcClient::new(HostRpcClient::new(scripted));

        futures::executor::block_on(scan_slot_excluding(
            &rpc,
            &metadata,
            [0x11; 32],
            7,
            &[0x22; 32],
            &[],
            true,
        ))
        .unwrap()
    }

    #[test]
    fn an_empty_period_offers_the_first_slot() {
        assert_eq!(scripted_find(&[None; SLOTS]), SlotSelection::Free(0));
    }

    #[test]
    fn the_slot_the_target_holds_is_found() {
        let mut slots = [None; SLOTS];
        slots[2] = Some([0x22; 32]);

        assert_eq!(scripted_find(&slots), SlotSelection::AlreadyAllocated(2));
    }

    #[test]
    fn a_table_filled_by_other_accounts_reports_full_rather_than_erroring() {
        let SlotSelection::Full { max, occupied } = scripted_find(&[Some([0x99; 32]); SLOTS])
        else {
            panic!("a full table should report Full");
        };

        assert_eq!(max, SLOTS as u32);
        // Every slot is reported, with the age the replacement rule needs.
        assert_eq!(occupied.len(), SLOTS);
        assert_eq!(occupied[0].seq, 0);
        assert_eq!(occupied[0].account_id, [0x99; 32]);
    }

    /// `since` values are what the replacement rule sorts on, so the scan has to
    /// carry them through rather than discard them.
    #[test]
    fn the_scan_reports_each_occupied_slots_age() {
        let metadata = Metadata::decode(FIXTURE).unwrap();
        let entries: Vec<String> = (0..SLOTS)
            .map(|seq| entry_with_since([0x99; 32], 1_000 + seq as u64))
            .collect();
        let scripted = ScriptedRpc::new(entries.iter().map(String::as_str).collect::<Vec<_>>());
        let rpc = RpcClient::new(HostRpcClient::new(scripted));

        let SlotSelection::Full { occupied, .. } = futures::executor::block_on(
            scan_slot_excluding(&rpc, &metadata, [0x11; 32], 7, &[0x22; 32], &[], true),
        )
        .unwrap() else {
            panic!("a full table should report Full");
        };

        assert_eq!(
            occupied.iter().map(|slot| slot.since).collect::<Vec<_>>(),
            (0..SLOTS).map(|seq| 1_000 + seq as u64).collect::<Vec<_>>(),
        );
    }

    /// The oldest slot wins, and the target's own slot is never a candidate.
    #[test]
    fn the_oldest_replaceable_slot_is_chosen() {
        let candidates = [
            occupied(0, [0x99; 32], 5_000),
            occupied(1, [0x22; 32], 1_000),
            occupied(2, [0x98; 32], 2_000),
        ];

        assert_eq!(
            replaceable_slot(&candidates, &[0x22; 32], 10_000, 60, &[]),
            Some(2),
        );
    }

    #[test]
    fn a_slot_inside_its_cooldown_is_not_replaceable() {
        let candidates = [occupied(0, [0x99; 32], 9_990)];

        assert_eq!(
            replaceable_slot(&candidates, &[0x22; 32], 10_000, 60, &[]),
            None,
        );
    }

    /// The runtime requires `now > since + cooldown`, so a slot at exactly the
    /// cooldown is still refused. Offering it means an extrinsic the chain
    /// rejects as invalid, which is not retried.
    #[test]
    fn the_cooldown_boundary_is_strict() {
        let candidates = [occupied(0, [0x99; 32], 1_000)];

        assert_eq!(
            replaceable_slot(&candidates, &[0x22; 32], 1_060, 60, &[]),
            None,
            "age exactly at the cooldown must not be offered",
        );
        assert_eq!(
            replaceable_slot(&candidates, &[0x22; 32], 1_061, 60, &[]),
            Some(0),
            "one second past the cooldown is replaceable",
        );
    }

    /// `Timestamp.Now` is milliseconds; ages are judged in seconds.
    #[test]
    fn the_chain_clock_is_read_in_seconds() {
        let scripted = ScriptedRpc::new(vec![r#""0x60ea000000000000""#]);
        let rpc = RpcClient::new(HostRpcClient::new(scripted));

        assert_eq!(
            futures::executor::block_on(read_chain_now_seconds(&rpc)).unwrap(),
            60,
        );
    }

    #[test]
    fn a_table_of_only_the_targets_own_and_cooling_slots_yields_nothing() {
        let candidates = [
            occupied(0, [0x22; 32], 1_000),
            occupied(1, [0x99; 32], 9_999),
        ];

        assert_eq!(
            replaceable_slot(&candidates, &[0x22; 32], 10_000, 60, &[]),
            None,
        );
    }

    #[test]
    fn an_excluded_slot_is_skipped_so_a_failed_replacement_moves_on() {
        let candidates = [
            occupied(0, [0x99; 32], 1_000),
            occupied(1, [0x98; 32], 2_000),
        ];

        assert_eq!(
            replaceable_slot(&candidates, &[0x22; 32], 10_000, 60, &[0]),
            Some(1),
        );
    }

    /// Equal ages resolve to the lowest seq, so retries do not oscillate.
    #[test]
    fn equal_ages_break_to_the_lowest_seq() {
        let candidates = [
            occupied(5, [0x99; 32], 1_000),
            occupied(2, [0x98; 32], 1_000),
        ];

        assert_eq!(
            replaceable_slot(&candidates, &[0x22; 32], 10_000, 60, &[]),
            Some(2),
        );
    }

    #[test]
    fn the_replacement_cooldown_comes_from_the_runtime() {
        let metadata = Metadata::decode(FIXTURE).unwrap();

        assert_eq!(replacement_cooldown(&metadata).unwrap(), 60);
    }

    /// Excluding a slot because a submission for it is in flight must not read as
    /// "the period is full": the free slot is coming back, and a caller that
    /// treats this as full would replace a live slot for nothing.
    #[test]
    fn an_excluded_free_slot_is_not_reported_as_a_full_period() {
        let metadata = Metadata::decode(FIXTURE).unwrap();
        // Only seq 9 is free, and the caller already excluded it.
        let mut entries: Vec<String> = (0..SLOTS - 1).map(|_| slot_entry([0x99; 32])).collect();
        entries.push("null".to_string());
        let scripted = ScriptedRpc::new(entries.iter().map(String::as_str).collect::<Vec<_>>());
        let rpc = RpcClient::new(HostRpcClient::new(scripted));

        let selection = futures::executor::block_on(scan_slot_excluding(
            &rpc,
            &metadata,
            [0x11; 32],
            7,
            &[0x22; 32],
            &[(SLOTS - 1) as u32],
            true,
        ))
        .unwrap();

        assert_eq!(selection, SlotSelection::FreeSlotsExcluded);
    }

    #[test]
    fn slot_context_layout() {
        let ctx = derive_slot_context(7, 3);
        assert_eq!(&ctx[..9], b"SSS_SLOT:");
        assert_eq!(&ctx[9..13], &7u32.to_be_bytes());
        assert_eq!(&ctx[13..17], &3u32.to_be_bytes());
        assert!(ctx[17..].iter().all(|&b| b == 0x20));
    }

    #[test]
    fn long_term_storage_context_layout() {
        let ctx = derive_long_term_storage_context(7, 3);
        assert_eq!(&ctx[..24], b"pop:polkadot.net/rsc-lts");
        assert_eq!(&ctx[24..28], &7u32.to_be_bytes());
        assert_eq!(ctx[28], 3);
        assert!(ctx[29..].iter().all(|&b| b == 0));
    }

    #[test]
    fn period_is_utc_day_index() {
        assert_eq!(current_period(86_400 * 20_000 + 5), 20_000);
    }

    #[test]
    fn long_term_storage_period_uses_chain_duration() {
        assert_eq!(
            current_long_term_storage_period(1_209_600 * 20 + 5, 1_209_600).unwrap(),
            20,
        );
    }

    #[test]
    fn allowance_entry_matches_runtime_field_codec() {
        let entry = StatementStoreAllowanceEntry {
            account_id: [0x42; 32],
            seq: 7,
            since: 99,
        };
        let encoded = entry.encode();

        assert_eq!(encoded, (entry.account_id, entry.seq, entry.since).encode());
        assert_eq!(
            decode_entry(&encoded).map(|e| e.account_id),
            Some(entry.account_id)
        );
        assert_eq!(
            StatementStoreAllowanceEntry::decode(&mut encoded.as_slice()).unwrap(),
            entry
        );
    }

    #[test]
    fn truncated_allowance_entry_has_no_account() {
        assert!(decode_entry(&[0x42; 32]).is_none());
    }
}
