#!/usr/bin/env bash
# Cross-product ring-VRF signing against a real signing-host CLI, driven
# through the `@parity/truapi` client.
#
# One product signs with another product's registered ring-VRF key; only the
# `context` grant in `peopl.paseo`'s local product config permits that. The
# sibling of `cross-product-storage-e2e.sh`, and the first end-to-end run in
# which a cross-product ring-VRF call is *granted* rather than refused.
#
# Unlike the storage sibling this reaches a chain: registering a ring-VRF key
# resolves a ring on the People chain.
#
# The runner serves one product per host process, so each phase is its own
# `truapi-host` run. They share one `--base-path`, which is what makes the
# signature genuinely cross-product: the key the later phases sign with was
# registered by a process that has already exited.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fixtures="rust/crates/truapi-host-cli/js/fixtures"
script="rust/crates/truapi-host-cli/js/cross-product-ringvrf-e2e.ts"
network="${E2E_NETWORK:-paseo-next-v2}"

# Kept between runs, unlike the storage sibling's temp directory. The first run
# registers a lite username on a real chain, and this directory holds the only
# copy of the account that owns it. Discarding it strands that name: the next
# run generates a fresh mnemonic, asks for the same username, and is told it is
# taken, permanently, because nothing can prove ownership of it any more.
#
# Point E2E_STATE_DIR elsewhere to run against a fresh identity, and expect to
# supply an unused --lite-username-prefix with it.
state="${E2E_STATE_DIR:-$repo_root/target/e2e/cross-product-ringvrf}"

# Only consulted when the state directory above holds no account yet, which
# is the first run on a machine or a deliberately fresh E2E_STATE_DIR. A
# machine that stranded the default name before this script kept its state
# cannot reach a single assertion without one. Lowercase ASCII letters only,
# at least six: digits and hyphens are refused.
lite_prefix="${E2E_LITE_USERNAME_PREFIX:-}"
prefix_arg=()
[ -n "$lite_prefix" ] && prefix_arg=(--lite-username-prefix "$lite_prefix")
mkdir -p "$state"

echo "==> building truapi-host"
cargo build -q -p truapi-host-cli
host="target/debug/truapi-host"

# Run one phase as one product. A phase that exits non-zero fails the script,
# including the phases whose assertion is that a signature was refused: the
# script distinguishes a refusal it expected from a host that fell over.
run_phase() {
  local phase="$1" product="$2"
  echo "==> $phase (as $product)"
  E2E_PHASE="$phase" "$host" signing-host \
    --network "$network" \
    --base-path "$state" \
      ${prefix_arg[@]+"${prefix_arg[@]}"} \
    --product-id "$product" \
    --product-config "$fixtures/peopl.paseo.json" \
    --product-config "$fixtures/dim2.paseo.json" \
    --auto-accept \
    --script "$script"
}

run_phase register peopl.paseo
run_phase sign-granted dim2.paseo
run_phase sign-untrusted stash.paseo
# Last, so the refusal above cannot have been the registration going away.
run_phase sign-again dim2.paseo
