//! Ring-VRF proofs for recycler entries and unload tokens.
//!
//! An unload presents two kinds of proof, and they are easy to confuse:
//!
//! * **Alias proofs** — one per entry being unloaded. Each proves the prover is
//!   a member of the recycler ring and yields the entry's *contextual alias*,
//!   which the call carries in its `aliases` argument. The proof and the alias
//!   come out of the same operation, so this module returns them together
//!   rather than letting a caller pair up mismatched halves.
//! * **The token proof** — one per extrinsic. Proves membership of whichever ring
//!   backs the token, and signs a message that includes the alias proofs, which is
//!   what binds the token to the exact set of entries it is spending on. A free
//!   token proves personhood; a paid one proves membership of the period's paid
//!   ring. The signed message is identical in both cases; only the ring, the key
//!   and the context differ.
//!
//! Ring membership is the caller's input. Fetching the ring at a pinned block
//! belongs to the chain layer; proving is deterministic given the members.

use parity_scale_codec::Encode;
use verifiable::GenerateVerifiable;
use verifiable::ring::RingDomainSize;
use verifiable::ring::bandersnatch::BandersnatchVrfVerifiable;

use super::call::RawEncoded;
use super::extension::{
    RECYCLER_ALIAS_CONTEXT, free_token_signing_context, paid_token_signing_context,
};
use crate::host_logic::coinage::derivation;
use crate::host_logic::coinage::error::CoinageError;
use crate::host_logic::coinage::types::{CoinAccountId, EntryIndex, PurseId};
use crate::runtime::statement_allowance::extension::blake2b256;
use crate::runtime::statement_allowance::proof::ring_vrf_proof;

/// One entry's contribution to an unload: its alias and the proof that earns it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EntryProof {
    /// The entry whose proof this is.
    pub index: EntryIndex,
    /// Contextual alias, for the call's `aliases` argument.
    pub alias: [u8; 32],
    /// Ring-VRF membership proof, for the extension's `alias_proofs`.
    pub proof: RawEncoded,
}

/// The contextual alias a recycler entry presents, without proving anything.
///
/// The same value a proof would yield, which is what lets a balance scan find an
/// entry's `RecyclersUnloaded` record without doing ring-VRF work.
pub fn recycler_alias(
    entropy: &[u8],
    purse: PurseId,
    index: EntryIndex,
) -> Result<[u8; 32], CoinageError> {
    let vrf_entropy = derivation::entry_ring_vrf_entropy(entropy, purse, index)?;
    let secret = BandersnatchVrfVerifiable::new_secret(vrf_entropy);
    let alias = BandersnatchVrfVerifiable::alias_in_context(&secret, RECYCLER_ALIAS_CONTEXT)
        .map_err(|error| {
            CoinageError::Internal(format!("recycler alias derivation failed: {error:?}"))
        })?;

    alias
        .as_ref()
        .try_into()
        .map_err(|_| CoinageError::Internal("recycler alias is not 32 bytes".to_string()))
}

/// Prove one entry's ring membership, returning its alias alongside the proof.
///
/// `members` is the recycler ring's included prefix. The entry's member key must
/// be in it or the prover fails, which is the honest outcome: an entry the chain
/// has not yet onboarded cannot be unloaded.
pub fn entry_membership_proof(
    domain: RingDomainSize,
    entropy: &[u8],
    purse: PurseId,
    index: EntryIndex,
    members: &[[u8; 32]],
    inherited_implication: &[u8],
) -> Result<EntryProof, CoinageError> {
    let vrf_entropy = derivation::entry_ring_vrf_entropy(entropy, purse, index)?;
    let secret = BandersnatchVrfVerifiable::new_secret(vrf_entropy);
    let member = BandersnatchVrfVerifiable::member_from_secret(&secret);
    let commitment = BandersnatchVrfVerifiable::open(domain, &member, members.iter().copied())
        .map_err(|error| {
            CoinageError::Internal(format!(
                "ring-VRF open failed for entry {index:?}: {error:?}"
            ))
        })?;

    let message = blake2b256(inherited_implication);
    let (proof, alias) =
        BandersnatchVrfVerifiable::create(commitment, &secret, RECYCLER_ALIAS_CONTEXT, &message)
            .map_err(|error| {
                CoinageError::Internal(format!(
                    "ring-VRF create failed for entry {index:?}: {error:?}"
                ))
            })?;

    Ok(EntryProof {
        index,
        alias: alias
            .as_ref()
            .try_into()
            .map_err(|_| CoinageError::Internal("recycler alias is not 32 bytes".to_string()))?,
        proof: RawEncoded(proof.into_inner()),
    })
}

/// Prove personhood for a free unload token.
///
/// Note this is a different ring and a different key from the alias proofs: the
/// prover here is the user's personhood member key in the People or LitePeople
/// ring, not any recycler entry. `members` must be that ring, and
/// `personhood_entropy` the bandersnatch entropy behind the personhood key.
///
/// The signed message covers the alias proofs, so the token is bound to exactly
/// the entries it is being spent on and cannot be replayed against a different
/// set. `alias_proofs` must therefore be the same slice, in the same order, that
/// the extension will carry.
pub fn free_token_proof(
    domain: RingDomainSize,
    personhood_entropy: [u8; 32],
    members: &[[u8; 32]],
    period: u32,
    counter: u32,
    alias_proofs: &[RawEncoded],
    inherited_implication: &[u8],
) -> Result<RawEncoded, CoinageError> {
    let context = free_token_signing_context(period, counter);

    let mut signed = alias_proofs.encode();
    signed.extend_from_slice(inherited_implication);
    let message = blake2b256(&signed);

    let proof = ring_vrf_proof(domain, personhood_entropy, members, &context, &message).map_err(
        |error| CoinageError::Internal(format!("free-token personhood proof failed: {error}")),
    )?;

    Ok(RawEncoded(proof))
}

/// Prove membership of the paid ring for a paid unload token.
///
/// `members` must be the paid-token ring the slot's key was onboarded into — a
/// different collection from both the recycler rings and the personhood ring — and
/// the domain must come from that collection's own ring size.
///
/// The signed message is the same as a free token's, so a paid token is bound to
/// its entries in exactly the same way. What differs is the context, which carries
/// the period and no counter: the slot is expressed by *which key signs*, not by
/// anything inside the proof.
pub fn paid_token_proof(
    domain: RingDomainSize,
    entropy: &[u8],
    members: &[[u8; 32]],
    period: u32,
    slot: u32,
    alias_proofs: &[RawEncoded],
    inherited_implication: &[u8],
) -> Result<RawEncoded, CoinageError> {
    let vrf_entropy = derivation::paid_token_ring_vrf_entropy(entropy, period, slot)?;
    let context = paid_token_signing_context(period);

    let mut signed = alias_proofs.encode();
    signed.extend_from_slice(inherited_implication);
    let message = blake2b256(&signed);

    let proof = ring_vrf_proof(domain, vrf_entropy, members, &context, &message)
        .map_err(|error| CoinageError::Internal(format!("paid-token proof failed: {error}")))?;

    Ok(RawEncoded(proof))
}

/// Prove control of the member key a paid-token join publishes.
///
/// `pay_for_recycler_unload_fee_token_with_*` carries a `proof_of_ownership` beside
/// the member key, checked by the call itself against the *origin account's*
/// encoded bytes. Its purpose is anti-front-running: without it, watching the pool
/// would let someone else's join publish your key.
///
/// The message is the joining account's 32 bytes, raw and unhashed — the same rule
/// as [`entry_ownership_proof`], and for the same reason.
pub fn paid_token_ownership_proof(
    entropy: &[u8],
    period: u32,
    slot: u32,
    joining_account: CoinAccountId,
) -> Result<RawEncoded, CoinageError> {
    let vrf_entropy = derivation::paid_token_ring_vrf_entropy(entropy, period, slot)?;
    let secret = BandersnatchVrfVerifiable::new_secret(vrf_entropy);
    let signature =
        BandersnatchVrfVerifiable::sign(&secret, &joining_account.0).map_err(|error| {
            CoinageError::Internal(format!("paid-token ownership signature failed: {error:?}"))
        })?;

    Ok(RawEncoded(signature.encode()))
}

/// Prove control of the member key an entry is about to publish.
///
/// `load_recycler_with_coin` carries a `proof_of_ownership` beside the member key,
/// and unlike every other proof in this pallet it is verified by the *call* rather
/// than by the extension — so its message cannot be the inherited implication,
/// which a dispatch cannot see. It signs the recycling coin's account: the fact
/// worth proving is that whoever controls that coin also controls the key being
/// published, which is what stops one wallet publishing another's key.
///
/// The message is the account's 32 bytes, raw and unhashed. Confirmed against the
/// shipped iOS-compatible top-up flow, which signs the external-asset holder's
/// account the same way for `load_recycler_with_external_asset_unpaid_batch` —
/// the same field, the same key, the same origin-account message.
pub fn entry_ownership_proof(
    entropy: &[u8],
    purse: PurseId,
    index: EntryIndex,
    coin_account: CoinAccountId,
) -> Result<RawEncoded, CoinageError> {
    let vrf_entropy = derivation::entry_ring_vrf_entropy(entropy, purse, index)?;
    let secret = BandersnatchVrfVerifiable::new_secret(vrf_entropy);
    let signature = BandersnatchVrfVerifiable::sign(&secret, &coin_account.0).map_err(|error| {
        CoinageError::Internal(format!("member-key ownership signature failed: {error:?}"))
    })?;

    Ok(RawEncoded(signature.encode()))
}

/// Aliases in the order the call expects them.
pub fn aliases_of(proofs: &[EntryProof]) -> Vec<[u8; 32]> {
    proofs.iter().map(|proof| proof.alias).collect()
}

/// Proofs in the order the extension expects them.
pub fn alias_proofs_of(proofs: &[EntryProof]) -> Vec<RawEncoded> {
    proofs.iter().map(|proof| proof.proof.clone()).collect()
}

#[cfg(test)]
mod tests {
    use parity_scale_codec::Decode;

    use crate::host_logic::coinage::derivation;
    use crate::runtime::statement_allowance::proof::RING_VRF_PROOF_LEN;

    use super::*;

    const ENTROPY: [u8; 32] = [7; 32];
    /// Smallest supported ring domain, per `domain_for_ring_exponent`.
    const DOMAIN: RingDomainSize = RingDomainSize::Domain11;

    /// Pad a ring out with unrelated members.
    fn with_fillers(mut members: Vec<[u8; 32]>) -> Vec<[u8; 32]> {
        for filler in 1u8..4 {
            let secret = BandersnatchVrfVerifiable::new_secret([filler; 32]);
            let member = BandersnatchVrfVerifiable::member_from_secret(&secret);
            members.push(member.as_ref().try_into().expect("32 bytes"));
        }
        members
    }

    /// A recycler ring holding one of our entries.
    fn ring_containing(purse: PurseId, index: EntryIndex) -> Vec<[u8; 32]> {
        with_fillers(vec![
            derivation::entry_member_key(&ENTROPY, purse, index).expect("derives"),
        ])
    }

    /// A personhood ring holding our personhood key — a different ring and a
    /// different key from any recycler entry.
    fn personhood_ring() -> Vec<[u8; 32]> {
        with_fillers(vec![
            crate::runtime::statement_allowance::proof::member_key(ENTROPY),
        ])
    }

    #[test]
    fn an_ownership_proof_is_bound_to_the_coin_being_recycled() {
        // The signature's whole job is to tie the member key to the coin paying
        // for it, so two coins must not produce the same proof — and the key's own
        // public must verify it.
        let purse = PurseId::MAIN;
        let index = EntryIndex(0);
        let first =
            entry_ownership_proof(&ENTROPY, purse, index, CoinAccountId([1; 32])).expect("signs");
        let second =
            entry_ownership_proof(&ENTROPY, purse, index, CoinAccountId([2; 32])).expect("signs");

        assert_ne!(first, second, "a proof for one coin must not serve another");
        assert_eq!(
            first.0.len(),
            64,
            "the call's field is a fixed 64 bytes, spliced raw"
        );

        let vrf_entropy =
            derivation::entry_ring_vrf_entropy(&ENTROPY, purse, index).expect("derives");
        let secret = BandersnatchVrfVerifiable::new_secret(vrf_entropy);
        let member = BandersnatchVrfVerifiable::member_from_secret(&secret);
        let signature =
            <BandersnatchVrfVerifiable as GenerateVerifiable>::Signature::decode(&mut &first.0[..])
                .expect("the signature round-trips");
        assert!(
            BandersnatchVrfVerifiable::verify_signature(&signature, &[1u8; 32], &member),
            "the published member key verifies its own ownership proof"
        );
    }

    #[test]
    fn an_alias_is_derivable_without_proving() {
        let alias = recycler_alias(&ENTROPY, PurseId::MAIN, EntryIndex(0)).expect("derives");
        let again = recycler_alias(&ENTROPY, PurseId::MAIN, EntryIndex(0)).expect("derives");

        assert_eq!(alias, again);
        assert_ne!(
            alias,
            recycler_alias(&ENTROPY, PurseId::MAIN, EntryIndex(1)).expect("derives")
        );
    }

    #[test]
    fn aliases_are_purse_scoped() {
        assert_ne!(
            recycler_alias(&ENTROPY, PurseId::MAIN, EntryIndex(0)).expect("derives"),
            recycler_alias(&ENTROPY, PurseId(1), EntryIndex(0)).expect("derives")
        );
    }

    #[test]
    fn proving_yields_the_same_alias_a_scan_would_derive() {
        // The scan path finds an entry's on-chain records by its alias, and the
        // unload call carries the alias the proof produced. If those two ever
        // disagreed, a scan could not see what an unload spent.
        let purse = PurseId::MAIN;
        let index = EntryIndex(0);
        let members = ring_containing(purse, index);

        let proved = entry_membership_proof(DOMAIN, &ENTROPY, purse, index, &members, &[9u8; 8])
            .expect("our member key is in the ring");

        assert_eq!(
            proved.alias,
            recycler_alias(&ENTROPY, purse, index).expect("derives")
        );
        assert_eq!(proved.index, index);
        assert_eq!(proved.proof.0.len(), RING_VRF_PROOF_LEN);
    }

    #[test]
    fn an_entry_outside_the_ring_cannot_prove_membership() {
        // An entry the chain has not onboarded must fail to prove rather than
        // produce something the runtime will reject.
        let members = ring_containing(PurseId::MAIN, EntryIndex(0));

        let outsider = entry_membership_proof(
            DOMAIN,
            &ENTROPY,
            PurseId::MAIN,
            EntryIndex(99),
            &members,
            &[9u8; 8],
        );

        assert!(matches!(outsider, Err(CoinageError::Internal(_))));
    }

    #[test]
    fn a_token_proof_binds_the_alias_set_it_is_spent_on() {
        let members = personhood_ring();
        let implication = [4u8; 8];
        let one = vec![RawEncoded(vec![1; 8])];
        let two = vec![RawEncoded(vec![1; 8]), RawEncoded(vec![2; 8])];

        let first = free_token_proof(DOMAIN, ENTROPY, &members, 1, 0, &one, &implication)
            .expect("our key is in the ring");
        let second = free_token_proof(DOMAIN, ENTROPY, &members, 1, 0, &two, &implication)
            .expect("our key is in the ring");

        // Ring-VRF proofs are randomized, so equality is not the property under
        // test; both must simply be well-formed and derived from different
        // messages. The binding itself is asserted on the message in
        // `extension::tests`.
        assert_eq!(first.0.len(), RING_VRF_PROOF_LEN);
        assert_eq!(second.0.len(), RING_VRF_PROOF_LEN);
    }

    #[test]
    fn a_token_proof_needs_the_personhood_ring_not_a_recycler_ring() {
        // The two proofs are easy to conflate. Handing the recycler ring to the
        // token prover must fail rather than quietly produce something the
        // runtime rejects.
        let recycler = ring_containing(PurseId::MAIN, EntryIndex(0));

        assert!(
            free_token_proof(
                DOMAIN,
                ENTROPY,
                &recycler,
                1,
                0,
                &[RawEncoded(vec![1; 8])],
                &[4u8; 8]
            )
            .is_err()
        );
    }

    #[test]
    fn the_two_orderings_stay_aligned() {
        let purse = PurseId::MAIN;
        let members = ring_containing(purse, EntryIndex(0));
        let proofs = vec![
            entry_membership_proof(DOMAIN, &ENTROPY, purse, EntryIndex(0), &members, &[1u8; 4])
                .expect("in the ring"),
        ];

        let aliases = aliases_of(&proofs);
        let alias_proofs = alias_proofs_of(&proofs);

        // The call's `aliases` and the extension's `alias_proofs` are positional
        // and must describe the same entries in the same order.
        assert_eq!(aliases.len(), alias_proofs.len());
        assert_eq!(aliases[0], proofs[0].alias);
        assert_eq!(alias_proofs[0], proofs[0].proof);
    }
}
