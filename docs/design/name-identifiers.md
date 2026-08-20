---
title: "Name Identifiers"
type: design
---

# Name Identifiers

Name identifiers are unique pointers of Products and Users. They are
labels registered in the [DotNS protocol](https://github.com/paritytech/dotns).

The protocol handles a name as its
[ENS-style namehash](https://docs.ens.domains/resolution/names#namehash),
originally specified in [EIP-137](https://eips.ethereum.org/EIPS/eip-137). It is computed as
`namehash(tldNode, keccak256(label))` in
[`LabelUtils`](https://github.com/paritytech/dotns/blob/main/contracts/utils/LabelUtils.sol),
so the stored identifier covers both the label and the Top Level Domain (TLD):

```
namehash("dot")         = keccak256(0x00…00 ++ keccak256("dot"))
                        = 0x3fce7d1364a893e213bc4212792b517ffc88f5b13b86c8ef9c8d390c3a1370ce
namehash("example.dot") = keccak256(namehash("dot") ++ keccak256("example"))
                        = 0x50cef3746492e11fe07821077c650ed11a908315a91b3a85b4a12afd21249605
```

#### Motivation

Three motivations argue for a well defined design:

- A test product must not be able to act as the mainnet product. If identity
  ignores the TLD, `game.test` controls the same accounts, permissions, and
  storage as `game.dot`, and a throwaway test deployment can mislead users
  when using real value.
- A developer who reuses one root mnemonic across networks gets the same
  product addresses on every network when identity ignores the TLD, which
  links their activity across networks. Deriving with the TLD keeps those
  address spaces unlinkable.
- Distinct identities per TLD reduce confusion across Polkadot App versions
  and web domains, because what the user sees named differently is also keyed
  differently.

The Individuality runtime takes this side for ring contexts:
[`build_product_context`](https://github.com/paritytech/individuality/blob/be61b7720e5345afff53f28b924f8bc129938e24/support/src/context.rs#L61-L80)
hashes the preimage `product/{name}.{tld}/{suffix}`, with the network suffix
an explicit argument. A host that derived ring contexts TLD-free would
disagree with the chain.

## Convention

Each network declares its own TLD, fixed at registry initialisation and
exposed by the
[`tld()` view function](https://github.com/paritytech/dotns/blob/main/contracts/registry/DotnsProtocolRegistry.sol)
of the DotNS protocol registry. The protocol owns the bare label, and the TLD
is appended when a label is rendered as a full name, so the same label is
served differently per network.

The identity is the full served name, TLD included. `game.test` and
`game.dot` are different products with different accounts, ring contexts,
entropy, permissions, and storage. Hosts MUST NOT strip or rewrite the TLD
when deriving or scoping, so nothing carries over between networks implicitly.
A product graduating from testnet to mainnet starts fresh, and any carry-over
MUST be an explicit migration.

The host still normalizes the spelling once, through
[`normalize_product_identifier`](../../rust/crates/truapi-platform/src/lib.rs):
trim, NFC-normalize, lowercase. A name MUST end in a TLD the host recognizes
(`DOTNS_TLDS`), with `localhost` and `localhost:{port}` accepted for
development. Everything else is rejected.

Every party that derives keys MUST apply the identical normalization. The
[mobile Account Holder](https://github.com/Polkadot-Community-Foundation/polkadot-app-ios-v2)
mirrors it, and
[host-spec C.5 to C.7](https://github.com/paritytech/host-spec/blob/main/spec/C-account-derivation.md)
plus the
[interop vectors](../../rust/crates/truapi-server/tests/wasm_crypto_vectors.rs)
pin it byte-for-byte. Everything keyed by a name id re-keys if the rule
drifts, so it MUST NOT be reimplemented outside
[`normalize_product_identifier`](../../rust/crates/truapi-platform/src/lib.rs)
and the
[reserved-id table](../../rust/crates/truapi-server/src/host_logic/product_account.rs).

#### Open Questions

- The built-in identifiers `uid.dot` and `peopl.dot` are pinned to `.dot` on
  every network, which gives the user one shared identity account and
  personhood domain across networks. Consistency with this convention says
  `uid.{tld}` per network, but that re-pins the mobile interop vectors and
  needs the Account Holder to move in lockstep.
- The recognized TLD list is compiled in (`DOTNS_TLDS`) while the registry
  already exposes the truth per network through `tld()`. The host should
  eventually learn the TLD from its configured network instead of a hardcoded
  list.
- Graduation needs its own design: a product that wants to carry state from
  testnet to mainnet needs a registered migration or alias, not implicit
  identity.

#### Use Cases

| Use Case                | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Navigation              | A host resolves the name a user typed or followed into the content it should load, via [`NavigateDecision`](../../rust/crates/truapi-server/src/host_logic/dotns.rs). Here the name is an address rather than an identity, and it is used verbatim.                                                                                                                                                                                                                                     |
| Product accounts        | The account tree of a product hangs off its identifier: `//product//{nameId}/{index}` ([RFC-0022](../rfcs/0022-account-derivations.md)), implemented in [`product_account.rs`](../../rust/crates/truapi-server/src/host_logic/product_account.rs). The built-ins `uid.dot` and `peopl.dot` are reserved identifiers in the same tree.                                                                                                                                                           |
| Ring contexts           | A personhood proof carries the identifier of the product it was made for, so no other product can replay it. [The ring-VRF signer](../../rust/crates/truapi-server/src/runtime/signing_host/ring_vrf.rs) builds the proof context ([RFC-0004](../rfcs/0004-ringlocation-redesign.md)), and the [ring-VRF registry](../../rust/crates/truapi-server/src/runtime/ring_vrf_registry.rs) records which keys belong to which identifier ([RFC-0024](../rfcs/0024-personhood-as-product.md)). |
| Per-product entropy     | Each product gets deterministic secret material ([RFC-0007](../rfcs/0007-derive-entropy.md)), and the identifier is what separates one product entropy space from another, in [`entropy.rs`](../../rust/crates/truapi-server/src/host_logic/entropy.rs).                                                                                                                                                                                                                                |
| Permissions and storage | Everything a host remembers about a product, from consent grants to stored values, sits under a `CoreStorageKey` built from the identifier, in [`truapi-platform`](../../rust/crates/truapi-platform/src/lib.rs).                                                                                                                                                                                                                                                                       |
| User identity           | The primary username a product may request ([RFC-0015](../rfcs/0015-get-user-id.md)) is itself a name identifier, and it points at the `uid.dot` identity account in [`product_account.rs`](../../rust/crates/truapi-server/src/host_logic/product_account.rs).                                                                                                                                                                                                                             |
