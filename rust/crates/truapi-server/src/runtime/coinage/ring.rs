//! Reading a recycler ring so an unload can prove membership in it.
//!
//! Unloading an entry means proving, in ring-VRF, that the entry's member key is
//! in its ring. The prover reconstructs the ring commitment from the member list,
//! so it needs the same members the runtime verifies against: the `included`
//! prefix of the ring, whole, in order.
//!
//! Two failure modes are worth naming, because neither announces itself:
//!
//! - **A missed page** yields a shorter member list, a different commitment, and
//!   a proof the runtime rejects. Paging therefore stops only at an absent page.
//! - **The wrong domain** — the ring's size fixes the FFT domain the proof is
//!   built over, so a proof for the wrong size does not verify. The size comes
//!   from the collection, never from the member count, because the member count
//!   is the *filled* part of a fixed-size ring.
//!
//! Every read is pinned to one block, so members, `included` and the ring's
//! revision describe one state of the chain rather than three.

use subxt::ext::scale_value::scale::decode_as_type;
use subxt::ext::scale_value::{Composite, Value, ValueDef};
use verifiable::ring::RingDomainSize;

use crate::host_logic::coinage::error::CoinageError;
use crate::host_logic::coinage::types::{
    DenominationExponent, RevisionIndex, RingIndex, RingLocation,
};
use crate::runtime::coinage::storage;
use crate::runtime::statement_allowance::extension::Metadata;
use crate::runtime::statement_allowance::proof::domain_for_ring_exponent;
use crate::runtime::statement_allowance::rpc::RpcClient;

/// Length of a bandersnatch ring member key.
const MEMBER_LEN: usize = 32;

/// A recycler ring as the prover needs it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RecyclerRing {
    /// Which ring, and at which membership revision.
    pub location: RingLocation,
    /// The `included` prefix of the ring's members, in ring order.
    pub members: Vec<[u8; 32]>,
    /// Proof domain the ring's size fixes.
    pub domain: RingDomainSize,
}

impl RecyclerRing {
    /// Whether `member_key` is in the ring's included prefix.
    ///
    /// A proof for a key outside it cannot be built, and asking first turns that
    /// into a clear refusal rather than an opaque prover error.
    pub fn includes(&self, member_key: &[u8; 32]) -> bool {
        self.members.contains(member_key)
    }
}

/// Read the ring an entry of `exponent` sits in, pinned to `at`.
pub async fn read_recycler_ring(
    rpc: &RpcClient,
    metadata: &Metadata,
    exponent: DenominationExponent,
    location: RingLocation,
    at: &str,
) -> Result<RecyclerRing, CoinageError> {
    let collection = storage::recycler_collection_id(exponent);
    let domain = read_ring_domain(rpc, metadata, &collection, at).await?;
    let members = read_ring_members(rpc, &collection, location.index, at).await?;

    Ok(RecyclerRing {
        location,
        members,
        domain,
    })
}

/// The membership revision a ring's root currently reports, pinned to `at`.
///
/// A proof is only valid against the revision it was built for, so this is read
/// fresh at proving time rather than taken from a local record: an entry observed
/// an hour ago may well name a revision the chain has since moved past.
pub async fn read_ring_revision(
    rpc: &RpcClient,
    metadata: &Metadata,
    exponent: DenominationExponent,
    ring: RingIndex,
    at: &str,
) -> Result<Option<RevisionIndex>, CoinageError> {
    let collection = storage::recycler_collection_id(exponent);
    let Some(raw) = read(rpc, &storage::ring_root_key(&collection, ring), at).await? else {
        return Ok(None);
    };
    let type_id = metadata
        .storage_value_type("Members", "Root")
        .ok_or_else(|| {
            CoinageError::Internal("Members.Root is absent from metadata".to_string())
        })?;
    let value = decode_as_type(&mut &raw[..], type_id, metadata.registry())
        .map_err(|error| CoinageError::Internal(format!("decoding a ring root failed: {error}")))?;

    revision_field(&value)
        .map(Some)
        .ok_or_else(|| CoinageError::Internal("a ring root carried no revision field".to_string()))
}

/// Pull the `revision` field out of a decoded ring root.
fn revision_field(value: &Value<u32>) -> Option<RevisionIndex> {
    let ValueDef::Composite(Composite::Named(fields)) = &value.value else {
        return None;
    };
    fields
        .iter()
        .find(|(name, _)| name == "revision")
        .and_then(|(_, value)| value.as_u128())
        .and_then(|revision| u32::try_from(revision).ok())
        .map(RevisionIndex)
}

/// The proof domain fixed by a collection's ring size.
async fn read_ring_domain(
    rpc: &RpcClient,
    metadata: &Metadata,
    collection: &[u8; 32],
    at: &str,
) -> Result<RingDomainSize, CoinageError> {
    let raw = read(rpc, &storage::collections_key(collection), at)
        .await?
        .ok_or_else(|| {
            CoinageError::Internal(
                "the recycler collection for this denomination does not exist on chain".to_string(),
            )
        })?;
    let type_id = metadata
        .storage_value_type("Members", "Collections")
        .ok_or_else(|| {
            CoinageError::Internal("Members.Collections is absent from metadata".to_string())
        })?;
    let value = decode_as_type(&mut &raw[..], type_id, metadata.registry()).map_err(|error| {
        CoinageError::Internal(format!("decoding a member collection failed: {error}"))
    })?;

    let exponent = ring_size_exponent(&value).ok_or_else(|| {
        CoinageError::Internal("a member collection carried no ring size".to_string())
    })?;
    domain_for_ring_exponent(exponent)
        .map_err(|error| CoinageError::Internal(format!("recycler ring domain: {error}")))
}

/// Pull the ring-size exponent out of a decoded collection.
///
/// The runtime spells the size as an enum (`R2e9`, `R2e10`, `R2e14`) rather than
/// a number, and an unrecognized variant is a runtime this layer cannot prove
/// against — so it fails rather than guessing a domain.
fn ring_size_exponent(value: &Value<u32>) -> Option<u8> {
    let ValueDef::Composite(Composite::Named(fields)) = &value.value else {
        return None;
    };
    let size = fields
        .iter()
        .find(|(name, _)| name == "ring_size")
        .map(|(_, value)| value)?;
    let ValueDef::Variant(variant) = &size.value else {
        return None;
    };

    match variant.name.as_str() {
        "R2e9" => Some(9),
        "R2e10" => Some(10),
        "R2e14" => Some(14),
        _ => None,
    }
}

/// Every included member of a ring, paged.
///
/// Stops at the first absent page, then truncates to the `included` prefix the
/// ring's status reports. An absent status means nothing is excluded.
async fn read_ring_members(
    rpc: &RpcClient,
    collection: &[u8; 32],
    ring: RingIndex,
    at: &str,
) -> Result<Vec<[u8; 32]>, CoinageError> {
    let mut members = Vec::new();
    for page in 0.. {
        let Some(bytes) = read(rpc, &storage::ring_keys_key(collection, ring, page), at).await?
        else {
            break;
        };
        let page_members = decode_ring_keys_page(&bytes)?;
        if page_members.is_empty() {
            break;
        }
        members.extend(page_members);
    }

    let status = storage::decode_ring_status(
        read(rpc, &storage::ring_keys_status_key(collection, ring), at).await?,
    )?;
    if (status.included as usize) < members.len() {
        members.truncate(status.included as usize);
    }

    Ok(members)
}

/// Decode one `RingKeys` page: a compact count then that many 32-byte keys.
fn decode_ring_keys_page(bytes: &[u8]) -> Result<Vec<[u8; 32]>, CoinageError> {
    use parity_scale_codec::{Compact, Decode};

    let mut cursor = bytes;
    let Compact(count) = Compact::<u32>::decode(&mut cursor)
        .map_err(|error| CoinageError::Internal(format!("ring keys page length: {error}")))?;

    let mut members = Vec::with_capacity(count as usize);
    for position in 0..count as usize {
        let start = position * MEMBER_LEN;
        let member: [u8; 32] = cursor
            .get(start..start + MEMBER_LEN)
            .ok_or_else(|| {
                CoinageError::Internal(format!(
                    "a ring keys page promised {count} members and delivered {position}"
                ))
            })?
            .try_into()
            .expect("the slice is MEMBER_LEN long; qed");
        members.push(member);
    }

    Ok(members)
}

/// One pinned storage read.
async fn read(rpc: &RpcClient, key: &[u8], at: &str) -> Result<Option<Vec<u8>>, CoinageError> {
    rpc.get_storage_at(key, at)
        .await
        .map_err(|error| CoinageError::SubscriptionError(error.to_string()))
}

#[cfg(test)]
mod tests {
    use parity_scale_codec::{Compact, Encode};
    use subxt_rpcs::RpcClient as HostRpcClient;

    use crate::runtime::statement_allowance::rpc::testing::ScriptedRpc;

    use super::*;

    const FIXTURE: &[u8] = include_bytes!("../../../tests/fixtures/paseo-next-v2-metadata.scale");

    fn metadata() -> Metadata {
        Metadata::decode(FIXTURE).expect("the fixture decodes")
    }

    fn exponent(value: i8) -> DenominationExponent {
        DenominationExponent::new(value).expect("exponent is in range")
    }

    fn location() -> RingLocation {
        RingLocation::new(RingIndex(3), RevisionIndex(1))
    }

    fn block_on<F: core::future::Future>(future: F) -> F::Output {
        futures::executor::block_on(future)
    }

    fn scripted(responses: &[String]) -> (ScriptedRpc, RpcClient) {
        let scripted = ScriptedRpc::new(responses.iter().map(String::as_str));
        let rpc = RpcClient::new(HostRpcClient::new(scripted.clone()));
        (scripted, rpc)
    }

    fn hex_response(bytes: &[u8]) -> String {
        format!("\"0x{}\"", hex::encode(bytes))
    }

    const NONE: &str = "null";

    /// `CollectionInfo` as the runtime encodes it:
    /// `owner ++ mode ++ ring_size ++ self_inclusion_delay`.
    ///
    /// The field order is the runtime's, and `ring_size` is third — a decoder that
    /// read the first byte it found would pick up the owner's variant instead.
    ///
    /// `RingExponent`'s variant indices *are* the exponents (9 / 10 / 14), not
    /// 0 / 1 / 2, which is exactly the kind of layout worth pinning in a fixture.
    fn collection_info(ring_size: u8) -> Vec<u8> {
        let mut encoded = vec![1u8]; // CollectionOwner::Local
        encoded.extend([9u8; 32]); // the owning account
        encoded.push(0u8); // RingMode::AppendOnly
        encoded.push(ring_size); // RingExponent
        encoded.push(0u8); // self_inclusion_delay: None
        encoded
    }

    fn page(members: &[[u8; 32]]) -> Vec<u8> {
        let mut encoded = Compact(members.len() as u32).encode();
        for member in members {
            encoded.extend_from_slice(member);
        }
        encoded
    }

    /// `RingStatus { total, included, .. }` — only `included` is read.
    fn ring_status(total: u32, included: u32) -> Vec<u8> {
        let mut encoded = total.to_le_bytes().to_vec();
        encoded.extend(included.to_le_bytes());
        encoded.push(0); // immutable_since: None
        encoded
    }

    #[test]
    fn a_ring_is_read_across_pages_and_truncated_to_included() {
        let first: Vec<[u8; 32]> = (0..3).map(|byte| [byte; 32]).collect();
        let second: Vec<[u8; 32]> = (3..5).map(|byte| [byte; 32]).collect();
        let (_scripted, rpc) = scripted(&[
            hex_response(&collection_info(9)),
            hex_response(&page(&first)),
            hex_response(&page(&second)),
            NONE.to_string(),
            hex_response(&ring_status(5, 4)),
        ]);

        let ring = block_on(read_recycler_ring(
            &rpc,
            &metadata(),
            exponent(4),
            location(),
            "0xfeed",
        ))
        .expect("reads");

        // Four included of five present: the fifth is onboarding and must not be
        // in the commitment the proof is built against.
        assert_eq!(ring.members.len(), 4);
        assert_eq!(ring.members[0], [0u8; 32]);
        assert_eq!(ring.members[3], [3u8; 32]);
        assert_eq!(ring.domain, RingDomainSize::Domain11);
        assert_eq!(ring.location, location());
        assert!(ring.includes(&[2u8; 32]));
        assert!(
            !ring.includes(&[4u8; 32]),
            "the excluded tail is not usable"
        );
    }

    #[test]
    fn the_ring_size_fixes_the_proof_domain() {
        for (variant, expected) in [
            (9u8, RingDomainSize::Domain11),
            (10, RingDomainSize::Domain12),
            (14, RingDomainSize::Domain16),
        ] {
            let (_scripted, rpc) = scripted(&[
                hex_response(&collection_info(variant)),
                hex_response(&page(&[[1u8; 32]])),
                NONE.to_string(),
                hex_response(&ring_status(1, 1)),
            ]);

            let ring = block_on(read_recycler_ring(
                &rpc,
                &metadata(),
                exponent(4),
                location(),
                "0xfeed",
            ))
            .expect("reads");

            assert_eq!(ring.domain, expected);
        }
    }

    #[test]
    fn an_unknown_ring_size_is_refused_rather_than_guessed() {
        // Guessing a domain produces a proof that does not verify, after an
        // unload token has been spent building it. A size the runtime's own enum
        // does not name is refused while decoding.
        let (_scripted, rpc) = scripted(&[hex_response(&collection_info(3))]);

        let refused = block_on(read_recycler_ring(
            &rpc,
            &metadata(),
            exponent(4),
            location(),
            "0xfeed",
        ))
        .expect_err("an unrecognized ring size stops the unload");

        assert!(
            refused.to_string().contains("member collection"),
            "unexpected refusal: {refused}"
        );
    }

    #[test]
    fn a_ring_size_this_layer_cannot_prove_against_yields_no_domain() {
        // The other half of the same guard, at the mapping rather than the
        // decoder: a future runtime that adds a ring size must stop this layer
        // instead of having it fall back to some domain that happens to compile.
        use subxt::ext::scale_value::Variant;

        let size = Value {
            value: ValueDef::Variant(Variant {
                name: "R2e11".to_string(),
                values: Composite::Unnamed(Vec::new()),
            }),
            context: 0u32,
        };
        let collection = Value {
            value: ValueDef::Composite(Composite::Named(vec![("ring_size".to_string(), size)])),
            context: 0u32,
        };

        assert_eq!(ring_size_exponent(&collection), None);
    }

    #[test]
    fn a_missing_collection_is_refused() {
        let (_scripted, rpc) = scripted(&[NONE.to_string()]);

        let refused = block_on(read_recycler_ring(
            &rpc,
            &metadata(),
            exponent(4),
            location(),
            "0xfeed",
        ))
        .expect_err("no collection means nothing to prove against");

        assert!(refused.to_string().contains("does not exist"));
    }

    #[test]
    fn a_truncated_page_is_an_error_not_a_short_ring() {
        // The dangerous version of this bug is silent: a page that promises four
        // members and carries two would otherwise produce a proof against a ring
        // the chain does not have.
        let mut truncated = Compact(4u32).encode();
        truncated.extend([1u8; 32]);
        let (_scripted, rpc) =
            scripted(&[hex_response(&collection_info(9)), hex_response(&truncated)]);

        let refused = block_on(read_recycler_ring(
            &rpc,
            &metadata(),
            exponent(4),
            location(),
            "0xfeed",
        ))
        .expect_err("a short page is a chain read this layer cannot interpret");

        assert!(refused.to_string().contains("delivered"));
    }

    #[test]
    fn every_read_is_pinned_to_the_same_block() {
        let (scripted, rpc) = scripted(&[
            hex_response(&collection_info(9)),
            hex_response(&page(&[[1u8; 32]])),
            NONE.to_string(),
            hex_response(&ring_status(1, 1)),
        ]);

        block_on(read_recycler_ring(
            &rpc,
            &metadata(),
            exponent(4),
            location(),
            "0xpinned",
        ))
        .expect("reads");

        for (method, params) in scripted.calls() {
            assert_eq!(method, "state_getStorage");
            assert!(
                params.contains("0xpinned"),
                "a ring read at a moving head could mix two rings: {params}"
            );
        }
    }
}
