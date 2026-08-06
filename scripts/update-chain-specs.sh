#!/usr/bin/env bash
# Refresh the bundled smoldot chain specs in rust/crates/truapi-provider/networks
# from their live chains.
#
# Each spec's genesis.stateRootHash is set from the chain's block 0, so the spec keeps matching the
# chain's genesis after a wipe; a stale genesis stops smoldot from syncing. Relay specs additionally
# get a fresh lightSyncState checkpoint, which reduces smoldot warp-sync time from ~12s to ~1-3s.
#
# The genesis and the checkpoint are what a light client trusts in place of syncing from block 0, so
# neither is taken on a single endpoint's word. Every reachable endpoint must serve the same genesis
# state root, and an endpoint other than the one that served the checkpoint must agree on the block
# it pins. A network with only one endpoint cannot be corroborated and says so.
#
# These specs are compiled into the @parity/truapi-provider wasm via include_str!, so a refresh only
# reaches consumers (e.g. dotli) after a new provider version is published and they bump to it.
#
# Usage: bash scripts/update-chain-specs.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SPECS_DIR="$PROJECT_DIR/rust/crates/truapi-provider/networks"

# Timeout (seconds) for all curl calls.
TIMEOUT=30

# Set when endpoints disagree about a genesis or a checkpoint. An unreachable endpoint is a routine
# outage, but a reachable one serving a different chain is not, so it fails the whole run.
INTEGRITY_FAILURES=0

# Health-check the candidate bootNodes (env var BOOTNODES) and keep only the reachable ones.
# Set env var SKIP_BOOTNODE_CHECK=true to leave them unchanged.
BOOTNODES_JS='
const fs = require("fs");
const net = require("net");

const skipBootnodeCheck = process.env.SKIP_BOOTNODE_CHECK === "true";

function parseMultiaddr(ma) {
  const parts = ma.split("/").filter(Boolean);
  let host = null, port = null;
  for (let i = 0; i < parts.length; i++) {
    if (["dns", "dns4", "dns6"].includes(parts[i]) && parts[i + 1]) {
      host = parts[i + 1];
    } else if (parts[i] === "ip4" && parts[i + 1]) {
      host = parts[i + 1];
    } else if (parts[i] === "tcp" && parts[i + 1]) {
      port = parseInt(parts[i + 1], 10);
    }
  }
  return { host, port };
}

function testBootnode(ma, timeoutMs = 5000) {
  return new Promise((resolve) => {
    const { host, port } = parseMultiaddr(ma);
    if (!host || !port) {
      resolve({ ma, healthy: false, reason: "unparseable" });
      return;
    }
    const socket = net.createConnection({ host, port, timeout: timeoutMs });
    socket.on("connect", () => {
      socket.destroy();
      resolve({ ma, healthy: true });
    });
    socket.on("timeout", () => {
      socket.destroy();
      resolve({ ma, healthy: false, reason: "timeout" });
    });
    socket.on("error", (err) => {
      socket.destroy();
      resolve({ ma, healthy: false, reason: err.code || err.message });
    });
  });
}

(async () => {
  const specPath = process.argv[1];
  const spec = JSON.parse(fs.readFileSync(specPath, "utf8"));

  if (skipBootnodeCheck) {
    console.log("  Bootnode health check SKIPPED, keeping existing bootnodes.");
    console.log("  Bootnodes (unchanged): " + spec.bootNodes.length);
    return;
  }

  const candidates = JSON.parse(process.env.BOOTNODES);
  console.log("  Testing " + candidates.length + " bootnodes (5s timeout each)...");
  const results = await Promise.all(candidates.map((bn) => testBootnode(bn)));
  const healthy = [];
  for (const r of results) {
    const short = r.ma.length > 80 ? r.ma.substring(0, 77) + "..." : r.ma;
    if (r.healthy) {
      console.log("    ok " + short);
      healthy.push(r.ma);
    } else {
      console.log("    x  " + short + " (" + r.reason + ")");
    }
  }
  console.log("  Healthy: " + healthy.length + "/" + candidates.length);
  if (healthy.length === 0) {
    console.log("  WARNING: No healthy bootnodes found, keeping original.");
  } else {
    spec.bootNodes = healthy;
    fs.writeFileSync(specPath, JSON.stringify(spec));
  }
  console.log("  Bootnodes: " + spec.bootNodes.length);
})();
'

# Corroborate a relay's warp-sync checkpoint against endpoints other than the one that served it.
#
# The checkpoint is the light client's root of trust, so it is not taken on one endpoint's word. Two
# things are checked against each peer in PEER_RPCS:
#
#   * The block it pins. CHECKPOINT_HEADER is the SCALE-encoded finalized header: its first 32 bytes
#     are the parent hash and the compact integer after them is the block number. The peer must
#     report the same parent hash for the canonical block at that height. Finalized blocks do not
#     reorg, so a peer that answers and disagrees is serving a different chain.
#   * The GRANDPA authority set, which is what the light client verifies finality against. A header
#     alone is not enough: a compromised endpoint could pair a genuine header with a forged
#     authority set. CHECKPOINT_AUTHORITY_SET is compared against the peer's own checkpoint. The
#     set id is compared first, because a peer that has crossed a set change legitimately reports a
#     different set; only a matching set id with differing authorities is an alarm.
#
# A peer that is behind the pinned height, or that cannot answer, is skipped.
CHECKPOINT_JS='
const header = process.env.CHECKPOINT_HEADER.replace(/^0x/, "");
const authoritySet = (process.env.CHECKPOINT_AUTHORITY_SET || "").replace(/^0x/, "");
const peers = JSON.parse(process.env.PEER_RPCS);
const parentHash = "0x" + header.slice(0, 64);

// SCALE compact integer at a byte offset, with the width it occupies.
function compactAt(hex, offset) {
  const byte = parseInt(hex.slice(offset * 2, offset * 2 + 2), 16);
  const mode = byte & 0b11;
  const width = mode === 0 ? 1 : mode === 1 ? 2 : mode === 2 ? 4 : 0;
  if (width === 0) throw new Error("big-integer compact values are not supported");
  const le = hex.slice(offset * 2, offset * 2 + width * 2);
  const bytes = le.match(/../g).map((b) => parseInt(b, 16));
  let value = 0;
  for (let i = bytes.length - 1; i >= 0; i--) value = value * 256 + bytes[i];
  return { value: value >>> 2, width };
}

// A GRANDPA AuthoritySet begins with current_authorities (a vector of 32-byte public key plus
// 8-byte weight), followed by the u64 set id. Both are needed: the id says whether two snapshots
// are even comparable, the authorities are what finality is checked against.
function splitAuthoritySet(hex) {
  if (hex.length === 0) return null;
  const count = compactAt(hex, 0);
  const authoritiesEnd = count.width + count.value * 40;
  if (hex.length < (authoritiesEnd + 8) * 2) return null;
  const setId = hex.slice(authoritiesEnd * 2, (authoritiesEnd + 8) * 2);
  const bytes = setId.match(/../g).map((b) => parseInt(b, 16));
  let number = 0n;
  for (let i = bytes.length - 1; i >= 0; i--) number = number * 256n + BigInt(bytes[i]);
  return {
    count: count.value,
    authorities: hex.slice(count.width * 2, authoritiesEnd * 2),
    setId,
    setNumber: number.toString(),
  };
}

async function rpc(url, method, params) {
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ id: 1, jsonrpc: "2.0", method, params }),
    signal: AbortSignal.timeout(Number(process.env.TIMEOUT || 30) * 1000),
  });
  return (await response.json()).result;
}

// Compare the authority set the peer carries in its own checkpoint. Returns an error string when
// the peer contradicts ours, or null when it agrees or cannot be compared.
async function authorityMismatch(peer) {
  const ours = splitAuthoritySet(authoritySet);
  if (ours === null) {
    console.log("    ? checkpoint carries no readable authority set, comparing the header only");
    return null;
  }
  const theirSpec = await rpc(peer, "sync_state_genSyncSpec", [true]);
  const theirs = splitAuthoritySet(
    ((theirSpec || {}).lightSyncState || {}).grandpaAuthoritySet
      ? theirSpec.lightSyncState.grandpaAuthoritySet.replace(/^0x/, "")
      : "",
  );
  if (theirs === null) {
    console.log("    ? " + peer + " served no authority set, comparing the header only");
    return null;
  }
  if (ours.setId !== theirs.setId) {
    console.log(
      "    ? " +
        peer +
        " is on GRANDPA set " +
        theirs.setNumber +
        ", the checkpoint is on " +
        ours.setNumber +
        "; cannot compare authorities",
    );
    return null;
  }
  if (ours.authorities !== theirs.authorities) {
    return (
      "authority sets differ within GRANDPA set " +
      ours.setNumber +
      " (" +
      ours.count +
      " vs " +
      theirs.count +
      " authorities)"
    );
  }
  console.log(
    "    ok " + ours.count + " GRANDPA authorities in set " + ours.setNumber + " agree with " + peer,
  );
  return null;
}

(async () => {
  const number = compactAt(header, 32).value;
  for (const peer of peers) {
    let peerParent;
    let mismatch;
    try {
      const hash = await rpc(peer, "chain_getBlockHash", [number]);
      if (!hash) {
        console.log("    ? " + peer + " is behind block " + number + ", cannot corroborate");
        continue;
      }
      peerParent = (await rpc(peer, "chain_getHeader", [hash])).parentHash;
      mismatch = await authorityMismatch(peer);
    } catch (error) {
      console.log("    ? " + peer + " did not answer (" + (error.message || error) + ")");
      continue;
    }
    if (peerParent.toLowerCase() !== parentHash.toLowerCase()) {
      console.log("    x " + peer + " disagrees at block " + number);
      console.log("      checkpoint parent " + parentHash);
      console.log("      peer parent       " + peerParent);
      process.exit(1);
    }
    if (mismatch !== null) {
      console.log("    x " + peer + " " + mismatch);
      process.exit(1);
    }
    console.log("    ok corroborated at block " + number + " by " + peer);
    return;
  }
  console.log("  WARNING: no independent endpoint could corroborate the checkpoint.");
})();
'

# Fetch the genesis state root.
fetch_state_root() {
  local rpc="$1"
  local block0
  block0=$(curl -s --max-time "$TIMEOUT" -H "Content-Type: application/json" \
    -d '{"id":1,"jsonrpc":"2.0","method":"chain_getBlockHash","params":[0]}' "$rpc" 2>/dev/null \
    | jq -r '.result // empty' 2>/dev/null)
  [ -z "$block0" ] && return 1
  curl -s --max-time "$TIMEOUT" -H "Content-Type: application/json" \
    -d "{\"id\":1,\"jsonrpc\":\"2.0\",\"method\":\"chain_getHeader\",\"params\":[\"$block0\"]}" "$rpc" 2>/dev/null \
    | jq -r '.result.stateRoot // empty' 2>/dev/null
}

# Refresh a spec from its live chain.
#
# Always sets genesis.stateRootHash from the chain's block 0, so the spec keeps matching the chain's
# genesis after a wipe. smoldot derives the block-announces protocol name from the genesis hash, so
# a stale genesis yields a name no peer offers, the substream fails with ProtocolNotAvailable, and
# smoldot can't sync the chain. sync_state_genSyncSpec is not used for the genesis, as it returns a
# genesis that serializes extra storage keys, so its computed hash does not match the real block 0.
#
# For a relay it also fetches sync_state_genSyncSpec and writes a fresh lightSyncState checkpoint
# for smoldot to warp-sync from (a relay has no parent to follow). A parachain follows its relay
# instead, so any committed lightSyncState is dropped. If that response carries bootNodes, they are
# health-checked and pruned to the reachable ones; otherwise existing bootNodes are preserved.
#
# Pass one or more RPC URLs; the first that serves block 0 is used.
refresh_spec() {
  local spec_file="$1"
  local is_relay="$2"
  shift 2

  echo "Refreshing $spec_file..."

  local fields="" rpc="" state_root="" peers=()
  for candidate in "$@"; do
    if [ -n "$state_root" ]; then
      peers+=("$candidate")
      continue
    fi
    state_root=$(fetch_state_root "$candidate") || true
    if [ -n "$state_root" ]; then
      rpc="$candidate"
      continue
    fi
    echo "  No block 0 from $candidate"
  done
  if [ -z "$state_root" ]; then
    echo "  ERROR: Could not fetch genesis state root for $spec_file from any RPC."
    return 1
  fi
  fields+="genesis.stateRootHash"

  # Every reachable endpoint must agree on the genesis, so one endpoint alone cannot redirect a
  # spec at a different chain.
  for peer in "${peers[@]:-}"; do
    [ -z "$peer" ] && continue
    local peer_root
    peer_root=$(fetch_state_root "$peer") || true
    if [ -n "$peer_root" ] && [ "$peer_root" != "$state_root" ]; then
      echo "  ERROR: $peer serves genesis state root $peer_root, $rpc serves $state_root."
      INTEGRITY_FAILURES=$((INTEGRITY_FAILURES + 1))
      return 1
    fi
  done

  # Relays read sync_state_genSyncSpec for their checkpoint; the same response also carries the
  # bootNodes. Pull only those two fields; jq drops the multi-MB genesis the response also returns.
  local light_sync_state="null" bootnodes="[]"
  if [ "$is_relay" = "true" ]; then
    local fresh
    fresh=$(curl -s --max-time "$TIMEOUT" -H "Content-Type: application/json" \
      -d '{"id":1,"jsonrpc":"2.0","method":"sync_state_genSyncSpec","params":[true]}' "$rpc" 2>/dev/null \
      | jq -c '{lightSyncState: .result.lightSyncState, bootNodes: .result.bootNodes}' 2>/dev/null || echo "null")
    light_sync_state=$(echo "$fresh" | jq -c '.lightSyncState // null')
    bootnodes=$(echo "$fresh" | jq -c '.bootNodes // []')
    # Without lightSyncState, smoldot can't sync a relay from a stateRootHash-only genesis, so fail.
    if [ "$light_sync_state" = "null" ]; then
      echo "  ERROR: Could not fetch lightSyncState from $rpc."
      return 1
    fi
    # The checkpoint is what the light client trusts instead of syncing from genesis, so a second
    # endpoint has to agree on the block it pins before it is compiled into the wasm.
    local checkpoint_header
    checkpoint_header=$(echo "$light_sync_state" | jq -r '.finalizedBlockHeader // .finalized_block_header // empty')
    if [ -z "$checkpoint_header" ]; then
      echo "  ERROR: lightSyncState from $rpc carries no finalized block header."
      return 1
    fi
    local checkpoint_authorities
    checkpoint_authorities=$(echo "$light_sync_state" | jq -r '.grandpaAuthoritySet // empty')
    if ! CHECKPOINT_HEADER="$checkpoint_header" \
      CHECKPOINT_AUTHORITY_SET="$checkpoint_authorities" \
      PEER_RPCS="$(printf '%s\n' "${peers[@]:-}" | jq -R . | jq -sc 'map(select(length > 0))')" \
      TIMEOUT="$TIMEOUT" node -e "$CHECKPOINT_JS"; then
      echo "  ERROR: the checkpoint from $rpc could not be corroborated; leaving $spec_file alone."
      INTEGRITY_FAILURES=$((INTEGRITY_FAILURES + 1))
      return 1
    fi
    fields+=" + lightSyncState"
  fi

  # lightSyncState can be hundreds of KB, so it goes via stdin; the small state root goes via env.
  echo "$light_sync_state" | STATE_ROOT="$state_root" \
    node -e '
      const fs = require("fs");
      let stdin = "";
      process.stdin.on("data", (chunk) => stdin += chunk);
      process.stdin.on("end", () => {
        const specPath = process.argv[1];
        const spec = JSON.parse(fs.readFileSync(specPath, "utf8"));
        spec.genesis = { stateRootHash: process.env.STATE_ROOT };
        const lss = JSON.parse(stdin);
        if (lss) spec.lightSyncState = lss;
        else delete spec.lightSyncState;
        fs.writeFileSync(specPath, JSON.stringify(spec));
      });
    ' "$SPECS_DIR/$spec_file"

  # Health-check bootNodes only when the chain actually advertises some.
  if [ "$(echo "$bootnodes" | jq 'length')" -gt 0 ]; then
    BOOTNODES="$bootnodes" node -e "$BOOTNODES_JS" "$SPECS_DIR/$spec_file"
    fields+=" + bootNodes"
  fi

  echo "  Updated $spec_file: $fields"
  echo ""
}

# A single network's outage should not block refreshing the others, so each call is non-fatal.

# Paseo Next v2 (the network dotli production runs on).
refresh_spec "paseo.json"                     true  "https://paseo-rpc.n.dwellir.com" \
                                                    "https://rpc.interweb-it.com/paseo" \
                                                    "https://rpc-paseo.stakeworld.io" || true
refresh_spec "paseo-next-v2-asset-hub.json"   false "https://paseo-asset-hub-next-rpc.polkadot.io" || true
refresh_spec "paseo-next-v2-bulletin.json"    false "https://paseo-bulletin-next-rpc.polkadot.io" || true
refresh_spec "paseo-next-v2-people.json"      false "https://paseo-people-next-system-rpc.polkadot.io" || true

# Previewnet.
refresh_spec "previewnet.json"                true  "https://previewnet.substrate.dev/relay/alice" || true
refresh_spec "previewnet-asset-hub.json"      false "https://previewnet.substrate.dev/asset-hub" || true
refresh_spec "previewnet-bulletin.json"       false "https://previewnet.substrate.dev/bulletin" || true
refresh_spec "previewnet-people.json"         false "https://previewnet.substrate.dev/people" || true

if [ "$INTEGRITY_FAILURES" -gt 0 ]; then
  echo "FAILED: $INTEGRITY_FAILURES spec(s) had endpoints disagreeing about the chain they serve."
  echo "Those specs were left unchanged. Investigate before publishing anything from this run."
  exit 1
fi

echo "Done. Bundled chain specs updated in rust/crates/truapi-provider/networks/"
echo "Publish a new @parity/truapi-provider so consumers pick up the refresh."
