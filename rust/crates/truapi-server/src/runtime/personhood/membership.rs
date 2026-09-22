//! Locating a provable ring membership for the person this host holds keys for.
//!
//! A candidate pairs a collection with the entropy backing it, because each
//! collection is its own alias space. Membership is settled by finding a ring
//! that includes the candidate's member key rather than from local state, so
//! two hosts holding the same keys agree about personhood.

use tracing::{debug, warn};

use crate::runtime::statement_allowance::StatementAllowanceError;
use crate::runtime::statement_allowance::extension::Metadata;
use crate::runtime::statement_allowance::rpc::RpcClient;

use super::collection::PersonhoodCollection;
use super::proof;
use super::ring::{self, RingParams};

/// A collection this device can derive aliases for, with the entropy backing
/// them. Each collection has its own entropy, so the pair travels together.
#[derive(Debug, Clone, Copy)]
pub struct CollectionCandidate {
    /// Collection to look for membership in.
    pub collection: PersonhoodCollection,
    /// Ring-VRF entropy for this collection.
    pub entropy: [u8; 32],
}

/// Our provable ring membership in one collection.
#[derive(Debug)]
pub struct CollectionMembership {
    /// Entropy whose member key is included in `ring`.
    pub entropy: [u8; 32],
    /// Ring snapshot the membership proof is built against.
    pub ring: RingParams,
}

impl CollectionMembership {
    /// The collection this membership proves.
    pub fn collection(&self) -> PersonhoodCollection {
        self.ring.collection
    }
}

/// Find the newest ring in `collection` (scanning up to `lookback` back from the
/// current index) that includes our member key. Reads the ring exponent once and
/// stops at the first match. Every read is pinned to one finalized block so the
/// snapshot is internally consistent; the pinned hash is recorded on the
/// returned [`RingParams`].
pub async fn find_including_ring(
    rpc: &RpcClient,
    metadata: &Metadata,
    collection: PersonhoodCollection,
    entropy: [u8; 32],
    lookback: u32,
) -> Result<Option<RingParams>, StatementAllowanceError> {
    let member = proof::member_key(entropy);
    let at = rpc.finalized_head().await?;
    let exponent = ring::read_ring_exponent(rpc, metadata, collection, &at).await?;
    let current = ring::read_current_ring_index_at(rpc, collection, &at).await?;
    let oldest = current.saturating_sub(lookback);
    for ring_index in (oldest..=current).rev() {
        let members = ring::read_ring_members_at(rpc, collection, ring_index, &at).await?;
        if members.contains(&member) {
            return Ok(Some(RingParams {
                collection,
                members,
                exponent,
                ring_index,
                block_hash: at,
            }));
        }
    }
    Ok(None)
}

/// Locate our including ring in each candidate collection, in the order given.
///
/// Membership in the ring is the availability test: a candidate whose member key
/// no ring includes is dropped, so the result is exactly the set of collections
/// this device can prove right now. A collection this chain does not run is
/// skipped rather than raised, because a chain without full personhood is not a
/// failure for a light-personhood device.
pub async fn find_including_rings(
    rpc: &RpcClient,
    metadata: &Metadata,
    candidates: &[CollectionCandidate],
    lookback: u32,
) -> Result<Vec<CollectionMembership>, StatementAllowanceError> {
    let mut memberships = Vec::new();
    let mut first_error = None;
    for candidate in candidates {
        let collection = candidate.collection;
        match find_including_ring(rpc, metadata, collection, candidate.entropy, lookback).await {
            Ok(Some(ring)) => {
                // A ring whose exponent has no proof domain cannot be proved
                // against, so it must not enter the set: selecting it would fail
                // after the collection was already chosen, with no fallback left.
                if let Err(err) = proof::domain_for_ring_exponent(ring.exponent) {
                    warn!(%collection, %err, "unusable ring exponent; skipping collection");
                    continue;
                }
                memberships.push(CollectionMembership {
                    entropy: candidate.entropy,
                    ring,
                });
            }
            Ok(None) => debug!(%collection, "no ring includes our member key"),
            // One collection's failure must not take down the others. A device
            // that can only prove light personhood should still get its
            // allowance when the full-personhood storage is unreadable.
            Err(err) => {
                warn!(%collection, %err, "could not resolve this collection");
                if first_error.is_none() {
                    first_error = Some(err);
                }
            }
        }
    }
    // Every candidate erroring is an outage, not an answer: reporting "not a
    // member" there would let a caller conclude the person has no personhood.
    match (memberships.is_empty(), first_error) {
        (true, Some(err)) => Err(err),
        _ => Ok(memberships),
    }
}

#[cfg(test)]
mod tests {
    use subxt_rpcs::RpcClient as HostRpcClient;

    use super::*;
    use crate::runtime::statement_allowance::rpc::testing::ScriptedRpc;
    use crate::runtime::statement_allowance::test_fixtures;

    /// A real `Members.Collections` value from the live People chain, whose
    /// `ring_size` is `R2e9`. Only that field is projected, so the same value
    /// serves either collection; hand-encoding one would mean encoding
    /// `CollectionOwner` and `RingMode` too, and a wrong guess would make these
    /// tests pass for the wrong reason.
    const LIVE_COLLECTION: &str = r#""0x000001043e000900""#;

    /// Entropy standing in for a reserved `peopl.<suffix>` person key.
    const PERSON_ENTROPY: [u8; 32] = [7u8; 32];

    /// One collection resolving: a head, its `Collections` value, ring index 0,
    /// a single-key ring page, then exhausted pages.
    fn resolving(entropy: [u8; 32]) -> Vec<String> {
        vec![
            r#""0xfinal""#.to_string(),
            LIVE_COLLECTION.to_string(),
            r#""0x00000000""#.to_string(),
            format!(r#""0x04{}""#, hex::encode(proof::member_key(entropy))),
            "null".to_string(),
            "null".to_string(),
        ]
    }

    fn scripted(responses: Vec<String>) -> RpcClient {
        let scripted = ScriptedRpc::new(responses.iter().map(String::as_str).collect::<Vec<_>>());
        RpcClient::new(HostRpcClient::new(scripted))
    }

    /// The whole path a backend handshake drives: reserved entropy in, a ring
    /// discovered on chain, and a proof opened against the members that ring
    /// actually holds.
    ///
    /// The cryptography itself is not re-proved here — `verifiable` owns that,
    /// and three other callers exercise `ring_vrf_proof`. What this pins is the
    /// wiring between them: that the discovered exponent maps to a usable
    /// domain, and that the proof is built over the discovered member set
    /// rather than over anything the caller supplied.
    #[test]
    fn a_discovered_membership_yields_a_proof_over_that_ring() {
        let candidates = [CollectionCandidate {
            collection: PersonhoodCollection::People,
            entropy: PERSON_ENTROPY,
        }];
        let rpc = scripted(resolving(PERSON_ENTROPY));

        let memberships = futures::executor::block_on(find_including_rings(
            &rpc,
            test_fixtures::people(),
            &candidates,
            u32::MAX,
        ))
        .expect("the scripted ring includes our member key");

        let membership = memberships.first().expect("one membership");
        assert_eq!(membership.collection(), PersonhoodCollection::People);
        assert_eq!(membership.entropy, PERSON_ENTROPY);
        assert_eq!(
            membership.ring.members,
            vec![proof::member_key(PERSON_ENTROPY)],
            "the proof must open over the ring's own members"
        );

        let domain = proof::domain_for_ring_exponent(membership.ring.exponent)
            .expect("a live ring exponent has a proof domain");
        let bytes = proof::ring_vrf_proof(
            domain,
            membership.entropy,
            &membership.ring.members,
            b"myapp.dot",
            b"challenge-bytes",
        )
        .expect("our member key is in the ring we opened against");
        assert_eq!(bytes.len(), 785, "a ring-VRF proof is 785 bytes");
    }

    /// A person in both collections proves against the widest-budget one.
    ///
    /// The handshake spends the first membership returned, so the order
    /// candidates are offered in is what decides which alias a backend sees.
    #[test]
    fn the_first_resolving_collection_is_the_one_offered_first() {
        let candidates = [
            CollectionCandidate {
                collection: PersonhoodCollection::People,
                entropy: PERSON_ENTROPY,
            },
            CollectionCandidate {
                collection: PersonhoodCollection::LitePeople,
                entropy: [9u8; 32],
            },
        ];
        let mut responses = resolving(PERSON_ENTROPY);
        responses.extend(resolving([9u8; 32]));
        let rpc = scripted(responses);

        let memberships = futures::executor::block_on(find_including_rings(
            &rpc,
            test_fixtures::people(),
            &candidates,
            u32::MAX,
        ))
        .expect("both collections resolve");

        assert_eq!(memberships.len(), 2, "both memberships are reported");
        assert_eq!(
            memberships[0].collection(),
            PersonhoodCollection::People,
            "the handshake takes the first, so People must lead"
        );
    }
}
