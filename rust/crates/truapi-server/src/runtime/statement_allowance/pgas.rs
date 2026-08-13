//! Asset Hub PGAS allowance claims.
//!
//! Mirrors the mobile wallet flow: pick the first unclaimed daily PGAS slot for
//! the target, prove LitePeople membership with the `AsPgas` transaction
//! extension, and submit `Pgas.claim_pgas` on Asset Hub.
//!
//! Two chains are involved. The ring and its revision come from the People
//! chain, where membership lives; the claim is submitted on Asset Hub, which
//! learns about People's rings through `MembersSubscriber`. A claim can only be
//! authorized against a revision Asset Hub has already imported, so the flow
//! waits for it rather than submitting a proof the runtime cannot verify.

use std::time::{Duration, Instant};

use scale_decode::DecodeAsType;
use sp_crypto_hashing::twox_128;
use thiserror::Error;

use super::extension::{AS_PGAS, Metadata, MetadataError};
use super::ring::{self, LITE_PEOPLE_IDENTIFIER, RingParams, blake2_128_concat};
use super::rpc::RpcClient;
use super::{
    ChainContext, StatementAllowanceError, duplicate_submit_error, extension, extrinsic, proof,
    slot,
};

/// How long to wait for Asset Hub to import the ring revision a proof is built
/// against before giving up.
const RING_REVISION_WAIT: Duration = Duration::from_secs(60);

/// Longest a single poll sleeps while waiting for a revision to land.
const RING_REVISION_POLL: Duration = Duration::from_secs(1);

/// Error while claiming a PGAS allowance.
#[derive(Debug, Error)]
pub enum PgasError {
    /// Asset Hub has moved past the revision the proof was built against, so it
    /// can never verify it. Resolve the ring again and rebuild the proof.
    #[error("Asset Hub pruned ring {ring_index} revision {revision}")]
    RingRevisionPruned {
        /// Ring the proof was built against.
        ring_index: u32,
        /// Revision the proof was built against.
        revision: u32,
    },
    /// Asset Hub had not imported the revision within the wait window.
    #[error("Asset Hub has not imported ring {ring_index} revision {revision}")]
    RingRevisionTimeout {
        /// Ring the proof was built against.
        ring_index: u32,
        /// Revision the proof was built against.
        revision: u32,
    },
}

/// One `MembersSubscriber.RingRoots` record, projected to the field that decides
/// whether a proof can be verified.
#[derive(Debug, DecodeAsType)]
struct RingCommitmentRecord {
    revision: u32,
}

/// Outcome of a PGAS claim.
pub struct PgasClaimOutcome {
    /// Asset Hub block containing the claim.
    pub block_hash: String,
    /// UTC day the claim was made for.
    pub day: u32,
    /// Slot claimed within that day.
    pub slot_index: u32,
    /// People ring index that authorized the claim.
    pub ring_index: u32,
}

/// `MembersSubscriber.RingRoots[(identifier, ring_index)]` storage key on Asset
/// Hub.
///
/// Both map keys are `Blake2_128Concat` here, unlike the People chain's
/// `Members` maps which take the collection identifier verbatim.
fn ring_roots_key(ring_index: u32) -> Vec<u8> {
    [
        twox_128(b"MembersSubscriber").as_slice(),
        twox_128(b"RingRoots").as_slice(),
        &blake2_128_concat(LITE_PEOPLE_IDENTIFIER),
        &blake2_128_concat(&ring_index.to_le_bytes()),
    ]
    .concat()
}

/// Everything one PGAS claim needs. Grouped rather than passed loose, matching
/// `RegistrationParams` in the statement-store path.
pub struct PgasClaim<'a> {
    /// Asset Hub connection the claim is submitted on.
    pub asset_hub_rpc: &'a RpcClient,
    /// Asset Hub metadata and signed-extension state, from the per-chain cache.
    pub asset_hub: &'a ChainContext,
    /// People-chain connection the ring revision is read from.
    pub people_rpc: &'a RpcClient,
    /// People-chain metadata.
    pub people_metadata: &'a Metadata,
    /// Our lite-person ring-VRF entropy.
    pub entropy: [u8; 32],
    /// Account the claim credits.
    pub target: &'a [u8; 32],
    /// Ring the membership proof is built against, already located on People.
    pub ring: &'a RingParams,
}

/// Claim one PGAS allowance for `target`, proving membership in the
/// already-located People `ring`.
///
/// A duplicate submission retries against a different slot, as the statement-store
/// and long-term-storage claims do: two hosts racing the same day both scan a free
/// slot before either lands.
pub async fn claim_pgas(
    params: PgasClaim<'_>,
) -> Result<PgasClaimOutcome, StatementAllowanceError> {
    let PgasClaim {
        asset_hub_rpc,
        asset_hub,
        people_rpc,
        people_metadata,
        entropy,
        target,
        ring,
    } = params;
    let asset_hub_metadata = asset_hub.metadata.as_ref();
    let asset_hub_state = &asset_hub.state;
    // The day is Asset Hub's, because its runtime checks the claim against its
    // own clock. Periods are a UTC day here as they are for statement store.
    let day = slot::current_period(slot::read_chain_now_seconds(asset_hub_rpc).await?);
    let revision = ring::read_ring_revision(
        people_rpc,
        people_metadata,
        ring.ring_index,
        &ring.block_hash,
    )
    .await?;
    await_ring_revision(asset_hub_rpc, asset_hub_metadata, ring.ring_index, revision).await?;

    let mut skipped_duplicate_slots = Vec::new();
    loop {
        let slot_index = slot::scan_pgas_slot_excluding(
            asset_hub_rpc,
            asset_hub_metadata,
            entropy,
            day,
            &skipped_duplicate_slots,
        )
        .await?;
        let context = slot::derive_pgas_context(day, slot_index);
        let call = extrinsic::build_claim_pgas_call(asset_hub_metadata, slot_index, target)?;
        let message = extension::build_proof_message_after_extension(
            asset_hub_metadata,
            &call,
            asset_hub_state,
            AS_PGAS,
        )?;
        let domain = proof::domain_for_ring_exponent(ring.exponent)?;
        let ring_proof = proof::ring_vrf_proof(domain, entropy, &ring.members, &context, &message)?;
        let extra = extrinsic::build_as_pgas_extra(
            asset_hub_metadata,
            &ring_proof,
            ring.ring_index,
            revision,
            day,
        )?;
        let claim = extrinsic::build_unsigned_extrinsic_with_extra(
            asset_hub_metadata,
            asset_hub_state,
            &call,
            AS_PGAS,
            &extra,
        )?;

        match asset_hub_rpc.submit_and_watch(&claim).await {
            Ok(block_hash) => {
                return Ok(PgasClaimOutcome {
                    block_hash,
                    day,
                    slot_index,
                    ring_index: ring.ring_index,
                });
            }
            Err(err) if duplicate_submit_error(&err.to_string()) => {
                skipped_duplicate_slots.push(slot_index);
            }
            Err(err) => return Err(err),
        }
    }
}

/// Wait until Asset Hub has imported `revision` of `ring_index`.
///
/// Public so a host can check propagation before offering a claim, and so the
/// live tests can exercise it without submitting.
///
/// Asset Hub keeps only the most recent roots per ring, so a revision can be
/// absent because it has not arrived yet or because it never will. Those need
/// different answers: the first is worth waiting for, the second means the proof
/// has to be rebuilt against a newer ring.
pub async fn await_ring_revision(
    rpc: &RpcClient,
    metadata: &Metadata,
    ring_index: u32,
    revision: u32,
) -> Result<(), StatementAllowanceError> {
    let value_type = metadata
        .storage_value_type("MembersSubscriber", "RingRoots")
        .ok_or(MetadataError::MissingStorageType {
            pallet: "MembersSubscriber",
            entry: "RingRoots",
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
            .map_err(|source| ring::RingError::DecodeAsType {
                context: "subscriber ring roots",
                source,
            })?;
            if records.iter().any(|record| record.revision == revision) {
                return Ok(());
            }
            // Every root Asset Hub holds is newer than ours, so ours is gone.
            if records
                .iter()
                .map(|record| record.revision)
                .min()
                .is_some_and(|oldest| oldest > revision)
            {
                return Err(PgasError::RingRevisionPruned {
                    ring_index,
                    revision,
                }
                .into());
            }
        }
        wait_before_next_ring_revision_poll(started, ring_index, revision).await?;
    }
}

/// Sleep before the next revision poll, or report the wait as exhausted.
async fn wait_before_next_ring_revision_poll(
    started: Instant,
    ring_index: u32,
    revision: u32,
) -> Result<(), StatementAllowanceError> {
    let Some(remaining) = RING_REVISION_WAIT.checked_sub(started.elapsed()) else {
        return Err(PgasError::RingRevisionTimeout {
            ring_index,
            revision,
        }
        .into());
    };
    futures_timer::Delay::new(remaining.min(RING_REVISION_POLL)).await;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Both map keys are hashed here, unlike the People chain's `Members` maps.
    #[test]
    fn subscriber_ring_key_hashes_both_map_keys() {
        let key = ring_roots_key(136);

        assert_eq!(key.len(), 16 + 16 + 16 + 32 + 16 + 4);
        assert_eq!(
            &key[48..80],
            LITE_PEOPLE_IDENTIFIER,
            "identifier follows its hash"
        );
        assert_eq!(
            &key[96..],
            &136u32.to_le_bytes(),
            "ring index is little-endian"
        );
    }

    /// A claim is authorized against one revision, so the day it is built for and
    /// the revision it proves must both reach the runtime unchanged.
    #[test]
    fn a_pruned_revision_is_distinguished_from_one_still_arriving() {
        let pruned = PgasError::RingRevisionPruned {
            ring_index: 2,
            revision: 100,
        };
        let waiting = PgasError::RingRevisionTimeout {
            ring_index: 2,
            revision: 100,
        };

        assert!(pruned.to_string().contains("pruned"));
        assert!(waiting.to_string().contains("has not imported"));
    }
}
