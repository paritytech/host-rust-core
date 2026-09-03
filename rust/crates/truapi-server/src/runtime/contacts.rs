//! The contact picker and the handles it hands out.
//!
//! A product never reads the contact list. It opens the host's picker, the host
//! draws an overlay from its own chat contacts, and the core turns the one
//! person the user selected into a handle.
//!
//! The handle is deliberately **not** per-product: the same contact yields the
//! same value in every product and on every host of this user. Per-product
//! handles were considered and rejected — the core resolves a handle when it
//! builds a transaction anyway, so scoping bought no safety a product could not
//! route around, and it cost the durable shared id that makes the API usable and
//! that survives contacts syncing between a user's hosts.
//!
//! Keyed on the session's root entropy source, which no product can reach, so
//! the mapping cannot be recovered by hashing candidate accounts.

use std::sync::Arc;

use parity_scale_codec::Encode;
use truapi::latest::AccountId;
use truapi_platform::HostContactBook;

/// Domain separator for the contact-handle key.
pub(crate) const CONTACT_HANDLE_CONTEXT: &[u8] = b"truapi-contact-handle";

/// Why a picker call cannot proceed.
///
/// Narrower than `ProductRuntimeError` on purpose: these are the only two ways
/// the capability itself is unavailable, so the mapping onto a wire error stays
/// total instead of needing an unreachable arm.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ContactsAccess {
    /// The host does not serve a contact picker.
    Unsupported,
    /// No active session.
    NotConnected,
}

/// Contacts access policy.
///
/// No execution-kind gate: unlike Chat, any product may ask. No permission
/// either — the user picking a contact in host UI is the consent. The adapter is
/// checked before the session so a host that serves no picker answers
/// `Unsupported` without an overlay ever being raised.
pub(crate) fn contacts_platform_for(
    has_session: bool,
    contacts: Option<&Arc<dyn truapi_platform::ContactsPlatform>>,
) -> Result<Arc<dyn truapi_platform::ContactsPlatform>, ContactsAccess> {
    let platform = contacts.cloned().ok_or(ContactsAccess::Unsupported)?;
    if !has_session {
        return Err(ContactsAccess::NotConnected);
    }
    Ok(platform)
}

/// Domain-separate the session's root entropy source into the contact-handle
/// key, so this key cannot collide with another derived from the same source.
pub(crate) fn handle_key_from_root_source(root_entropy_source: &[u8; 32]) -> [u8; 32] {
    blake2b256_keyed(root_entropy_source, CONTACT_HANDLE_CONTEXT)
}

/// The handle one contact is known by, across every product and every host of
/// this user.
///
/// `handle_key` comes from the session's root entropy source, which both host
/// roles hold and no product can reach. That is what makes this a real
/// obfuscation rather than an encoding: an adversary cannot recover the mapping
/// by hashing candidate accounts, because People-chain accounts are enumerable
/// but the key is not guessable.
///
/// Product-independent on purpose — one contact is one handle everywhere, and
/// the key is uniform across a user's hosts because the wallet supplies the same
/// root source to each.
pub(crate) fn contact_handle(handle_key: &[u8; 32], account: &AccountId) -> [u8; 32] {
    blake2b256_keyed(&account.encode(), handle_key)
}

/// Recover the account a handle names, by re-minting over the accounts the host
/// knows.
///
/// The mint is deterministic, so resolution needs no stored handle table: hash
/// each candidate and compare. Returns `None` when no contact matches, which is
/// what a stale or forged handle looks like.
///
/// This is the seam the signing path will use to turn a product-supplied handle
/// into a recipient. Substituting it into transaction construction is not wired
/// yet, so a product can pick a contact but cannot yet pay one.
pub fn resolve_handle(
    handle_key: &[u8; 32],
    handle: &[u8; 32],
    book: &HostContactBook,
) -> Option<AccountId> {
    book.contacts
        .iter()
        .map(|contact| contact.account)
        .find(|account| &contact_handle(handle_key, account) == handle)
}

fn blake2b256_keyed(message: &[u8], key: &[u8]) -> [u8; 32] {
    blake2b_simd::Params::new()
        .hash_length(32)
        .key(key)
        .hash(message)
        .as_bytes()
        .try_into()
        .expect("hash_length(32) configures BLAKE2b output to exactly 32 bytes; qed")
}

#[cfg(test)]
mod tests {
    use super::*;
    use truapi_platform::HostContact;

    const ALICE: AccountId = [10u8; 32];
    const BOB: AccountId = [11u8; 32];

    /// One identity's handle key, derived the way a live session's is.
    fn key() -> [u8; 32] {
        handle_key_from_root_source(&[1u8; 32])
    }

    /// A second identity's, to stand in for another user.
    fn other_key() -> [u8; 32] {
        handle_key_from_root_source(&[2u8; 32])
    }

    fn book(accounts: &[AccountId]) -> HostContactBook {
        HostContactBook {
            contacts: accounts
                .iter()
                .map(|account| HostContact {
                    account: *account,
                    display_name: Some("name".to_string()),
                })
                .collect(),
        }
    }

    #[test]
    fn one_contact_has_one_handle_regardless_of_product() {
        // The point of the design: a handle is a durable shared id, so it takes
        // no product as input and cannot vary by caller.
        assert_eq!(
            contact_handle(&key(), &ALICE),
            contact_handle(&key(), &ALICE)
        );
    }

    #[test]
    fn two_contacts_have_different_handles() {
        assert_ne!(contact_handle(&key(), &ALICE), contact_handle(&key(), &BOB));
    }

    #[test]
    fn two_users_have_different_handles_for_one_contact() {
        // Keyed per identity, so the same person is a different pseudonym to a
        // different user.
        assert_ne!(
            contact_handle(&key(), &ALICE),
            contact_handle(&other_key(), &ALICE)
        );
    }

    #[test]
    fn the_handle_key_is_not_the_root_source_it_came_from() {
        // Domain separation: the key is not the raw entropy source, so it cannot
        // collide with another use of the same secret.
        let source = [1u8; 32];
        assert_ne!(handle_key_from_root_source(&source), source);
    }

    #[test]
    fn a_handle_does_not_reveal_the_account() {
        // Not a strength claim -- just that the account is not passed through.
        assert_ne!(contact_handle(&key(), &ALICE), ALICE);
    }

    #[test]
    fn a_handle_resolves_back_to_its_account() {
        let handle = contact_handle(&key(), &BOB);
        assert_eq!(
            resolve_handle(&key(), &handle, &book(&[ALICE, BOB])),
            Some(BOB)
        );
    }

    #[test]
    fn an_unknown_handle_resolves_to_nothing() {
        // A handle for a contact the host no longer knows, or one a product
        // invented, must not resolve to some other account.
        let handle = contact_handle(&key(), &BOB);
        assert_eq!(resolve_handle(&key(), &handle, &book(&[ALICE])), None);
        assert_eq!(
            resolve_handle(&key(), &[0u8; 32], &book(&[ALICE, BOB])),
            None
        );
    }

    #[test]
    fn a_handle_does_not_resolve_under_another_handle_key() {
        let handle = contact_handle(&key(), &BOB);
        assert_eq!(
            resolve_handle(&other_key(), &handle, &book(&[ALICE, BOB])),
            None
        );
    }

    #[test]
    fn an_empty_book_discloses_nothing_beyond_being_empty() {
        // An empty list reaches the product as `NoContacts`, so it does reveal
        // that the user has none -- a deliberate trade so a product can tell a
        // retryable dismissal from a pointless one. It reveals nothing further:
        // no count, and no handle resolves against it.
        let empty = HostContactBook { contacts: vec![] };
        assert_eq!(
            resolve_handle(&key(), &contact_handle(&key(), &ALICE), &empty),
            None
        );
    }

    #[test]
    fn the_product_wire_surface_is_the_picker_and_nothing_else() {
        // The contact list must not be reachable from a product. This asserts
        // the dispatch table itself, so adding a list or subscribe method to the
        // `Contacts` trait fails here rather than shipping.
        let contacts: Vec<&str> = crate::generated::wire_table::WIRE_TABLE
            .iter()
            .map(|entry| entry.method)
            .filter(|method| method.starts_with("contacts_"))
            .collect();
        assert_eq!(contacts, vec!["contacts_pick"]);
    }

    #[test]
    fn a_picked_outcome_carries_nothing_but_a_handle() {
        // Encoded width pins the payload: one discriminant plus 32 bytes leaves
        // no room for a name, an account, or a count to ride along.
        let picked = truapi::latest::ContactPickOutcome::Picked {
            handle: contact_handle(&key(), &ALICE),
        };
        assert_eq!(picked.encode().len(), 33);
    }

    #[test]
    fn the_outcomes_that_disclose_nothing_encode_to_one_byte() {
        // Dismissed and NoContacts carry a discriminant and nothing else.
        assert_eq!(
            truapi::latest::ContactPickOutcome::Dismissed.encode().len(),
            1
        );
        assert_eq!(
            truapi::latest::ContactPickOutcome::NoContacts
                .encode()
                .len(),
            1
        );
    }

    #[test]
    fn a_missing_platform_is_unsupported_before_a_missing_session() {
        // Ordering matters: a host that serves no picker must not raise an
        // overlay, and must not report a session problem it does not have.
        assert_eq!(
            contacts_platform_for(false, None).err(),
            Some(ContactsAccess::Unsupported)
        );
        assert_eq!(
            contacts_platform_for(true, None).err(),
            Some(ContactsAccess::Unsupported)
        );
    }
}
