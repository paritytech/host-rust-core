//! Asset Hub PGAS allowance claims.
//!
//! This mirrors the mobile wallet flow: derive a product account, select the
//! first free daily PGAS alias, prove Lite People membership with the
//! `AsPgas` transaction extension, and submit `Pgas.claim_pgas`.

use std::time::{Duration, Instant};

use parity_scale_codec::{Decode, Encode};
use scale_decode::DecodeAsType;
use sp_crypto_hashing::{blake2_128, twox_128};
use thiserror::Error;
use verifiable::Error as VerifiableError;
use verifiable::GenerateVerifiable;
use verifiable::ring::bandersnatch::BandersnatchVrfVerifiable;

use super::statement_allowance::StatementAllowanceError;
use super::statement_allowance::extension::{
    ChainState, Metadata, MetadataError, build_proof_message_after_extension,
};
use super::statement_allowance::extrinsic::build_unsigned_extrinsic_with_extra;
use super::statement_allowance::proof::{domain_for_ring_exponent, ring_vrf_proof};
use super::statement_allowance::ring::{self, RingParams};
use super::statement_allowance::rpc::RpcClient;

const AS_PGAS: &str = "AsPgas";
const PGAS_CONTEXT_PREFIX: &[u8] = b"pop:gas:";
const LITE_PEOPLE_IDENTIFIER: &[u8; 32] = b"pop:polkadot.network/people-lite";
const MILLIS_PER_DAY: u64 = 86_400_000;
const OPTION_SOME: u8 = 1;
const RING_REVISION_WAIT: Duration = Duration::from_secs(60);

/// Failure while selecting or claiming a PGAS allowance.
#[derive(Debug, Error)]
pub enum PgasAllowanceError {
    /// Shared chain, metadata, ring, proof, or submission failure.
    #[error(transparent)]
    Allowance(#[from] StatementAllowanceError),
    /// Asset Hub had no timestamp value.
    #[error("Timestamp.Now is unavailable")]
    TimestampUnavailable,
    /// Asset Hub timestamp storage did not decode as milliseconds.
    #[error("Timestamp.Now decode failed: {0}")]
    TimestampDecode(#[source] parity_scale_codec::Error),
    /// PGAS maximum-claims constant did not decode as a `u32`.
    #[error("Pgas.MaxClaimsPerPeriodPerLitePerson decode failed: {0}")]
    MaxClaimsDecode(#[source] parity_scale_codec::Error),
    /// No daily PGAS alias remained unused.
    #[error("no free PGAS slot on day {day} (max {max})")]
    NoFreeSlot {
        /// UTC day scanned.
        day: u32,
        /// Number of configured Lite People claims.
        max: u32,
    },
    /// Bandersnatch alias derivation failed.
    #[error("PGAS alias derivation failed: {0:?}")]
    Alias(VerifiableError),
    /// Asset Hub ring commitment storage failed to decode.
    #[error("MembersSubscriber.RingRoots decode failed: {0}")]
    RingRootsDecode(#[source] scale_decode::Error),
    /// Asset Hub has already pruned the People ring revision used by the proof.
    #[error("Asset Hub pruned ring {ring_index} revision {revision}")]
    RingRevisionPruned {
        /// People ring index.
        ring_index: u32,
        /// Revision selected on People.
        revision: u32,
    },
    /// Asset Hub did not import the People ring revision in time.
    #[error("timed out waiting for Asset Hub ring {ring_index} revision {revision}")]
    RingRevisionTimeout {
        /// People ring index.
        ring_index: u32,
        /// Revision selected on People.
        revision: u32,
    },
}

/// Successful on-chain PGAS claim.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PgasClaimOutcome {
    /// Asset Hub block containing the claim.
    pub block_hash: String,
    /// UTC day used by the claim.
    pub day: u32,
    /// Free slot selected within that day.
    pub slot_index: u32,
    /// People ring index authorizing the claim.
    pub ring_index: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Encode, Decode)]
struct ClaimPgasCallArgs {
    slot_index: u32,
    target: [u8; 32],
}

#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
struct ClaimPgasInfo {
    proof: Vec<u8>,
    ring_index: u32,
    revision: u32,
    collection: u8,
    day: u32,
}

#[derive(Debug, DecodeAsType)]
struct RingCommitmentRecord {
    revision: u32,
}

/// Claim one PGAS allowance for `target`.
pub async fn claim_pgas(
    asset_hub_rpc: &RpcClient,
    asset_hub_metadata: &Metadata,
    asset_hub_state: &ChainState,
    people_rpc: &RpcClient,
    people_metadata: &Metadata,
    entropy: [u8; 32],
    target: &[u8; 32],
    ring: &RingParams,
) -> Result<PgasClaimOutcome, PgasAllowanceError> {
    let day = current_day(asset_hub_rpc).await?;
    let max = max_lite_people_claims(asset_hub_metadata)?;
    let slot_index = first_free_slot(asset_hub_rpc, entropy, day, max).await?;
    let context = pgas_context(day, slot_index);
    let call = build_claim_pgas_call(asset_hub_metadata, slot_index, target)?;
    let revision = ring::read_ring_revision(
        people_rpc,
        people_metadata,
        ring.ring_index,
        &ring.block_hash,
    )
    .await?;
    await_ring_revision(asset_hub_rpc, asset_hub_metadata, ring.ring_index, revision).await?;
    let message =
        build_proof_message_after_extension(asset_hub_metadata, &call, asset_hub_state, AS_PGAS)?;
    let domain = domain_for_ring_exponent(ring.exponent)?;
    let proof = ring_vrf_proof(domain, entropy, &ring.members, &context, &message)?;
    let extra = build_as_pgas_extra(asset_hub_metadata, &proof, ring.ring_index, revision, day)?;
    let extrinsic = build_unsigned_extrinsic_with_extra(
        asset_hub_metadata,
        asset_hub_state,
        &call,
        AS_PGAS,
        &extra,
    )?;
    let block_hash = asset_hub_rpc.submit_and_watch(&extrinsic).await?;
    Ok(PgasClaimOutcome {
        block_hash,
        day,
        slot_index,
        ring_index: ring.ring_index,
    })
}

async fn await_ring_revision(
    rpc: &RpcClient,
    metadata: &Metadata,
    ring_index: u32,
    revision: u32,
) -> Result<(), PgasAllowanceError> {
    let value_type = metadata
        .storage_value_type("MembersSubscriber", "RingRoots")
        .ok_or_else(|| {
            PgasAllowanceError::Allowance(
                MetadataError::MissingStorageType {
                    pallet: "MembersSubscriber",
                    entry: "RingRoots",
                }
                .into(),
            )
        })?;
    let started = Instant::now();
    loop {
        if let Some(bytes) = rpc.get_storage(&ring_roots_key(ring_index)).await? {
            let mut input = bytes.as_slice();
            let records = Vec::<RingCommitmentRecord>::decode_as_type(
                &mut input,
                value_type,
                metadata.registry(),
            )
            .map_err(PgasAllowanceError::RingRootsDecode)?;
            if records.iter().any(|record| record.revision == revision) {
                return Ok(());
            }
            if records
                .iter()
                .map(|record| record.revision)
                .min()
                .is_some_and(|oldest| oldest > revision)
            {
                return Err(PgasAllowanceError::RingRevisionPruned {
                    ring_index,
                    revision,
                });
            }
        }
        if started.elapsed() >= RING_REVISION_WAIT {
            return Err(PgasAllowanceError::RingRevisionTimeout {
                ring_index,
                revision,
            });
        }
        futures_timer::Delay::new(Duration::from_secs(1)).await;
    }
}

async fn current_day(rpc: &RpcClient) -> Result<u32, PgasAllowanceError> {
    let bytes = rpc
        .get_storage(&timestamp_now_key())
        .await?
        .ok_or(PgasAllowanceError::TimestampUnavailable)?;
    let millis = u64::decode(&mut &bytes[..]).map_err(PgasAllowanceError::TimestampDecode)?;
    Ok((millis / MILLIS_PER_DAY) as u32)
}

fn max_lite_people_claims(metadata: &Metadata) -> Result<u32, PgasAllowanceError> {
    let bytes = metadata
        .constant("Pgas", "MaxClaimsPerPeriodPerLitePerson")
        .ok_or_else(|| {
            PgasAllowanceError::Allowance(
                MetadataError::MissingConstant {
                    pallet: "Pgas",
                    constant: "MaxClaimsPerPeriodPerLitePerson",
                }
                .into(),
            )
        })?;
    u32::decode(&mut &bytes[..]).map_err(PgasAllowanceError::MaxClaimsDecode)
}

async fn first_free_slot(
    rpc: &RpcClient,
    entropy: [u8; 32],
    day: u32,
    max: u32,
) -> Result<u32, PgasAllowanceError> {
    for slot_index in 0..max {
        let alias = pgas_alias(entropy, day, slot_index)?;
        if rpc
            .get_storage(&claimed_gas_alias_key(day, &alias))
            .await?
            .is_none()
        {
            return Ok(slot_index);
        }
    }
    Err(PgasAllowanceError::NoFreeSlot { day, max })
}

fn pgas_context(day: u32, slot_index: u32) -> [u8; 32] {
    let mut context = [0u8; 32];
    context[..PGAS_CONTEXT_PREFIX.len()].copy_from_slice(PGAS_CONTEXT_PREFIX);
    let day_start = PGAS_CONTEXT_PREFIX.len();
    context[day_start..day_start + 4].copy_from_slice(&day.to_le_bytes());
    context[day_start + 4..day_start + 8].copy_from_slice(&slot_index.to_le_bytes());
    context
}

fn pgas_alias(
    entropy: [u8; 32],
    day: u32,
    slot_index: u32,
) -> Result<[u8; 32], PgasAllowanceError> {
    let secret = BandersnatchVrfVerifiable::new_secret(entropy);
    BandersnatchVrfVerifiable::alias_in_context(&secret, &pgas_context(day, slot_index))
        .map_err(PgasAllowanceError::Alias)
}

fn build_claim_pgas_call(
    metadata: &Metadata,
    slot_index: u32,
    target: &[u8; 32],
) -> Result<Vec<u8>, PgasAllowanceError> {
    let indices = metadata.call_indices("Pgas", "claim_pgas")?;
    let mut call = Vec::with_capacity(2 + 4 + 32);
    call.extend_from_slice(&indices);
    ClaimPgasCallArgs {
        slot_index,
        target: *target,
    }
    .encode_to(&mut call);
    Ok(call)
}

fn build_as_pgas_extra(
    metadata: &Metadata,
    proof: &[u8],
    ring_index: u32,
    revision: u32,
    day: u32,
) -> Result<Vec<u8>, PgasAllowanceError> {
    let (claim, lite_people) =
        metadata.extension_info_and_field_variant_indices(AS_PGAS, "Claim", "LitePeople")?;
    let mut extra = Vec::with_capacity(2 + proof.len() + 16);
    extra.push(OPTION_SOME);
    extra.push(claim);
    ClaimPgasInfo {
        proof: proof.to_vec(),
        ring_index,
        revision,
        collection: lite_people,
        day,
    }
    .encode_to(&mut extra);
    Ok(extra)
}

fn timestamp_now_key() -> Vec<u8> {
    [
        twox_128(b"Timestamp").as_slice(),
        twox_128(b"Now").as_slice(),
    ]
    .concat()
}

fn claimed_gas_alias_key(day: u32, alias: &[u8; 32]) -> Vec<u8> {
    [
        twox_128(b"Pgas").as_slice(),
        twox_128(b"ClaimedGasAliases").as_slice(),
        &day.to_be_bytes(),
        &blake2_128_concat(alias),
    ]
    .concat()
}

fn ring_roots_key(ring_index: u32) -> Vec<u8> {
    [
        twox_128(b"MembersSubscriber").as_slice(),
        twox_128(b"RingRoots").as_slice(),
        &blake2_128_concat(LITE_PEOPLE_IDENTIFIER),
        &blake2_128_concat(&ring_index.to_le_bytes()),
    ]
    .concat()
}

fn blake2_128_concat(value: &[u8]) -> Vec<u8> {
    [blake2_128(value).as_slice(), value].concat()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn context_matches_mobile_wallet_layout() {
        let context = pgas_context(0x0102_0304, 0x0506_0708);
        assert_eq!(&context[..8], b"pop:gas:");
        assert_eq!(&context[8..12], &[0x04, 0x03, 0x02, 0x01]);
        assert_eq!(&context[12..16], &[0x08, 0x07, 0x06, 0x05]);
        assert_eq!(&context[16..], &[0; 16]);
    }

    #[test]
    fn claimed_alias_storage_key_uses_big_endian_day_and_blake_concat() {
        let alias = [0x42; 32];
        let key = claimed_gas_alias_key(0x0102_0304, &alias);
        assert_eq!(
            &key[32..36],
            &[0x01, 0x02, 0x03, 0x04],
            "Identity day key must match the mobile wallet's big-endian bytes",
        );
        assert_eq!(&key[52..], &alias);
    }

    #[test]
    fn subscriber_ring_key_blake_concats_both_map_keys() {
        let key = ring_roots_key(136);
        assert_eq!(key.len(), 32 + 16 + 32 + 16 + 4);
        assert_eq!(&key[48..80], LITE_PEOPLE_IDENTIFIER);
        assert_eq!(&key[96..], &136u32.to_le_bytes());
    }

    #[test]
    fn claim_payload_matches_mobile_wallet_field_order() {
        let encoded = ClaimPgasInfo {
            proof: vec![0xaa, 0xbb],
            ring_index: 7,
            revision: 9,
            collection: 1,
            day: 11,
        }
        .encode();
        let decoded = ClaimPgasInfo::decode(&mut &encoded[..]).unwrap();
        assert_eq!(
            decoded,
            ClaimPgasInfo {
                proof: vec![0xaa, 0xbb],
                ring_index: 7,
                revision: 9,
                collection: 1,
                day: 11,
            }
        );
    }
}
