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

## Convention

Each network declares its own TLD, fixed at registry initialisation and
exposed by the
[`tld()` view function](https://github.com/paritytech/dotns/blob/main/contracts/registry/DotnsProtocolRegistry.sol)
of the DotNS protocol registry. The protocol owns the bare label, and the TLD
is appended when a label is rendered as a full name, so the same label is
served differently per network.

The served, TLD-full form is for routing only. For identity, the host
normalizes once through
[`normalize_product_identifier`](../../rust/crates/truapi-platform/src/lib.rs):
trim, NFC-normalize, lowercase, strip the recognized TLD listed in
`DOTNS_TLDS`. `localhost` and `localhost:{port}` pass through. Everything else
is rejected. All uses above except navigation and username display take the
canonical result.

The label is the identity, the TLD is routing. Hosts MUST derive and scope by
the TLD-free canonical form, so a product keeps its accounts, aliases,
permissions, and storage when it graduates from testnet to mainnet or the user
switches networks. ENS gets the same continuity with one `.eth` everywhere
plus a disposable `.test`.

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

#### Use Cases

| Use Case                | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Navigation              | A host resolves the name a user typed or followed into the content it should load, via [`NavigateDecision`](../../rust/crates/truapi-server/src/host_logic/dotns.rs). This is the only use that keeps the served name intact, TLD included, because here the name is an address.                                                                                                                                                                                                        |
| Product accounts        | The account tree of a product hangs off its identifier: `//product//{nameId}/{index}` ([RFC-0022](../rfcs/0022-account-derivations.md)), implemented in [`product_account.rs`](../../rust/crates/truapi-server/src/host_logic/product_account.rs). The built-ins `uid` and `peopl` are reserved identifiers in the same tree.                                                                                                                                                           |
| Ring contexts           | A personhood proof carries the identifier of the product it was made for, so no other product can replay it. [The ring-VRF signer](../../rust/crates/truapi-server/src/runtime/signing_host/ring_vrf.rs) builds the proof context ([RFC-0004](../rfcs/0004-ringlocation-redesign.md)), and the [ring-VRF registry](../../rust/crates/truapi-server/src/runtime/ring_vrf_registry.rs) records which keys belong to which identifier ([RFC-0024](../rfcs/0024-personhood-as-product.md)). |
| Per-product entropy     | Each product gets deterministic secret material ([RFC-0007](../rfcs/0007-derive-entropy.md)), and the identifier is what separates one product entropy space from another, in [`entropy.rs`](../../rust/crates/truapi-server/src/host_logic/entropy.rs).                                                                                                                                                                                                                                |
| Permissions and storage | Everything a host remembers about a product, from consent grants to stored values, sits under a `CoreStorageKey` built from the identifier, in [`truapi-platform`](../../rust/crates/truapi-platform/src/lib.rs).                                                                                                                                                                                                                                                                       |
| User identity           | The primary username a product may request ([RFC-0015](../rfcs/0015-get-user-id.md)) is itself a name identifier, and it points at the `uid` identity account in [`product_account.rs`](../../rust/crates/truapi-server/src/host_logic/product_account.rs).                                                                                                                                                                                                                             |
