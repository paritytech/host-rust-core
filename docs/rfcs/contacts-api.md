---
title: "Contacts API"
owner: "@filippovecchiato"
status: draft
---

# RFC — Contacts API

## Summary

A product asks the Host to let the user pick a contact. The Host renders an overlay from its Chat
workers' chat lists, the user selects one person, and the product receives one opaque handle — never
the list, a name, or an account. The handle is not an address: the core resolves it when building a
transaction.

## Motivation

Each user has a different alias and account per context, so no handle identifies a person across
products, and a contact list is how a user keeps that private notebook. Products cannot use any of it
today, so users paste raw keys. But "send this NFT to a friend" needs one recipient the user chose,
not the address book — so this exposes the interaction rather than the list.

## Approach

Contacts come from the chat lists the Host's chat extensions hold; Hosts keep their own schema
and no new address book is imposed. A Host exposes them through one method and **renders the picker
itself**, so names never cross to the product — which matters because a Host's only name for a contact
is often a globally correlatable People-chain username.

```rust
enum ContactPickOutcome {
  Picked { handle: [u8; 32] },
  Dismissed,
  NoContacts,
}

fn host_contacts_pick() -> Result<ContactPickOutcome, HostContactsPickError>;
```

Three outcomes because the retry decision differs: `Dismissed` is worth offering again, `NoContacts`
is not, and a Host with no picker answers `Unsupported`. No permission is requested — the user
selecting a contact is the consent.

The handle is one value per contact, the same in every product and on every Host of this user, keyed
on the user's entropy so no product can turn it back into an account. It is not an address: a product
names it as the recipient and the core substitutes the account when it builds the transaction. A
product-scoped address is not derivable at all, which is why the handle is resolvable rather than
directly usable.

## Trade-offs

- Substitution at signing is not wired yet: a product can pick a contact but not yet pay one.
- WASM hosts and Rust embedders only; UniFFI hosts have no contacts channel.
- `NoContacts` reveals whether the user has any contacts — zero-or-not, never a count.
- No product-rendered contact UI, every selection is a user interaction, one contact per call,
  read-only.
- Dropped: returning the list scoped per product (`display_name` was a correlator no scoping fixed,
  and it needed a permission over the whole social graph); per-product handles (forfeit a durable
  shared id, break under contact sync); returning the chat account (transactable, but a global
  identifier any two products can join on); an unkeyed handle, or one keyed on the root account key
  (recoverable by hashing enumerable accounts).

## Open questions

How a handle is named in a payload and substituted at signing.
