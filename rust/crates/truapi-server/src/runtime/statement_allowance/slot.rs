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

/// The account id occupying a slot entry, if the storage value is present.
/// Entry = `account_id(32) ‖ seq(u32 LE) ‖ since(u64 LE)`.
fn entry_account_id(bytes: &[u8]) -> Option<[u8; 32]> {
    let mut input = bytes;
    let entry = StatementStoreAllowanceEntry::decode(&mut input).ok()?;
    let _ = (entry.seq, entry.since);
    Some(entry.account_id)
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
        .and_then(|bytes| entry_account_id(&bytes)))
}

/// Outcome of scanning for a slot to register `target` in.
pub enum SlotSelection {
    /// A free `seq` we should claim.
    Free(u32),
    /// `target` already holds `seq` this period; no registration needed.
    AlreadyAllocated(u32),
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
    for seq in 0..max {
        let alias = slot_alias(entropy, period, seq)?;
        let key = statement_store_allowance_key(period, &alias);
        match rpc.get_storage(&key).await? {
            None => {
                if first_free.is_none() && !excluded.contains(&seq) {
                    first_free = Some(seq);
                }
            }
            Some(bytes) => {
                if reuse_existing && entry_account_id(&bytes) == Some(*target) {
                    return Ok(SlotSelection::AlreadyAllocated(seq));
                }
            }
        }
    }
    first_free
        .map(SlotSelection::Free)
        .ok_or_else(|| SlotError::NoFreeStatementStoreSlot { period, max }.into())
}

/// The slot `target` holds at `period`, if any. `entropy` is our bandersnatch
/// entropy.
///
/// Answers only "is an allowance already in place", so unlike
/// [`scan_slot_excluding`] it ignores free slots and a fully occupied table is
/// not an error. Callers on a request path use it to avoid resolving a ring
/// (which pages through `Members.RingKeys`) when no submission is needed.
pub async fn find_allocated_slot(
    rpc: &RpcClient,
    metadata: &Metadata,
    entropy: [u8; 32],
    period: u32,
    target: &[u8; 32],
) -> Result<Option<u32>, StatementAllowanceError> {
    let max = max_slots(metadata)?;
    for seq in 0..max {
        let alias = slot_alias(entropy, period, seq)?;
        let key = statement_store_allowance_key(period, &alias);
        if let Some(bytes) = rpc.get_storage(&key).await?
            && entry_account_id(&bytes) == Some(*target)
        {
            return Ok(Some(seq));
        }
    }
    Ok(None)
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
        format!(r#""0x{}""#, hex::encode((account, 0u32, 0u64).encode()))
    }

    /// Run `find_allocated_slot` for `[0x22; 32]` against a scripted period
    /// whose slot occupancy is `slots`.
    fn scripted_find(slots: &[Option<[u8; 32]>]) -> Option<u32> {
        let metadata = Metadata::decode(FIXTURE).unwrap();
        let entries: Vec<String> = slots
            .iter()
            .map(|slot| slot.map_or_else(|| "null".to_string(), slot_entry))
            .collect();
        let scripted = ScriptedRpc::new(entries.iter().map(String::as_str));
        let rpc = RpcClient::new(HostRpcClient::new(scripted));

        futures::executor::block_on(find_allocated_slot(
            &rpc,
            &metadata,
            [0x11; 32],
            7,
            &[0x22; 32],
        ))
        .unwrap()
    }

    #[test]
    fn an_empty_period_holds_no_slot() {
        assert_eq!(scripted_find(&[None; SLOTS]), None);
    }

    #[test]
    fn the_slot_the_target_holds_is_found() {
        let mut slots = [None; SLOTS];
        slots[2] = Some([0x22; 32]);

        assert_eq!(scripted_find(&slots), Some(2));
    }

    #[test]
    fn a_table_filled_by_other_accounts_is_not_an_error() {
        assert_eq!(scripted_find(&[Some([0x99; 32]); SLOTS]), None);
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
        assert_eq!(entry_account_id(&encoded), Some(entry.account_id));
        assert_eq!(
            StatementStoreAllowanceEntry::decode(&mut encoded.as_slice()).unwrap(),
            entry
        );
    }

    #[test]
    fn truncated_allowance_entry_has_no_account() {
        assert_eq!(entry_account_id(&[0x42; 32]), None);
    }
}
