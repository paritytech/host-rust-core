# Reproduction: cross-product ring VRF gate (host-rust-core#373)

Spike branch, not for merging. It shows two things on the current `main`:

1. `create_account_proof` / `ring_vrf_sign` with a foreign key handle fail
   with `NotAllowlisted` unconditionally, because nothing feeds the allowlist.
2. The gate logic is complete. Giving it any source makes the same calls
   succeed. The spike source is an env var,
   `TRUAPI_RING_VRF_ALLOWLIST="owner:caller[,owner:caller]"`, consulted at the
   two `runtime.rs` frontend checks and the `signing_host.rs` /
   `pairing_host.rs` duplicates (see the single commit touching `truapi-server`).

## Run

Build the CLI, then use one managed signing-host session for both phases so
the wallet (and its key registry) is shared.

Phase A, host serves `peopl.dot`, registers `Index(1)` in the people-lite ring
and signs as owner:

```bash
truapi-host signing-host --product-id peopl.dot --auto-accept \
  exec '/script ./js/scripts/rfc24-cross-a-register.ts'
```

Phase B, same session, host now serves `dim2.dot` and uses peopl.dot's handle:

```bash
truapi-host signing-host --product-id dim2.dot --auto-accept \
  exec '/script ./js/scripts/rfc24-cross-b-consume.ts'
```

Expected without the env var (one `X_PRODUCT` line per call):

```
list(anonymized): OK
list(publicKey): OK
getAccountAlias(foreign): OK
createAccountProof(foreign): ERR NotAllowlisted
ringVrfSign(foreign): ERR NotAllowlisted
```

Rerun phase B with the spike source:

```bash
TRUAPI_RING_VRF_ALLOWLIST=peopl.dot:dim2.dot truapi-host signing-host \
  --product-id dim2.dot --auto-accept \
  exec '/script ./js/scripts/rfc24-cross-b-consume.ts'
```

Expected:

```
ringVrfSign(foreign): OK <64-byte signature, same bytes as phase A ownerSig>
createAccountProof(foreign): ERR NotMember   (past the gate; the fresh key is not in the ring yet)
```
