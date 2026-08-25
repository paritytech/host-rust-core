#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
BIN="$ROOT/target/debug/truapi-host"
SCRIPT="$ROOT/rust/crates/truapi-host-cli/js/scripts/pair-and-sign-smoke.ts"
PRODUCT_ID="${PRODUCT_ID:-truapi-playground.dot}"
TIMEOUT_SECONDS="${TRUAPI_E2E_TIMEOUT_SECONDS:-300}"

[ -x "$BIN" ] || { echo "missing $BIN, run: cargo build -p truapi-host-cli" >&2; exit 2; }

SIGNER_BASE="${TRUAPI_HOST_BASE_PATH:-$(mktemp -d /tmp/truapi-multi-signer.XXXXXX)}"
PAIRING_A_BASE="$(mktemp -d /tmp/truapi-multi-pair-a.XXXXXX)"
PAIRING_B_BASE="$(mktemp -d /tmp/truapi-multi-pair-b.XXXXXX)"
LOG_DIR="$(mktemp -d /tmp/truapi-multi-pair-logs.XXXXXX)"
SIGNER_BASE_OWNED=1
if [ -n "${TRUAPI_HOST_BASE_PATH:-}" ]; then
  SIGNER_BASE_OWNED=0
fi

SIGNER_PID=""
PAIRING_PIDS=()

stop_process() {
  local process_id="$1"
  [ -n "$process_id" ] || return 0
  kill -TERM "$process_id" 2>/dev/null || true
  wait "$process_id" 2>/dev/null || true
}

process_running() {
  local process_id="$1"
  local state
  state="$(ps -p "$process_id" -o stat= 2>/dev/null || true)"
  [ -n "$state" ] && [ "${state#Z}" = "$state" ]
}

cleanup() {
  local status=$?
  stop_process "$SIGNER_PID"
  for process_id in "${PAIRING_PIDS[@]}"; do
    stop_process "$process_id"
  done
  rm -rf -- "$PAIRING_A_BASE" "$PAIRING_B_BASE"
  if [ "$SIGNER_BASE_OWNED" -eq 1 ]; then
    rm -rf -- "$SIGNER_BASE"
  fi
  if [ "$status" -eq 0 ]; then
    rm -rf -- "$LOG_DIR"
  else
    echo "E2E logs preserved at $LOG_DIR" >&2
  fi
  return "$status"
}
trap cleanup EXIT

wait_for_pattern() {
  local log_path="$1"
  local pattern="$2"
  shift 2
  local process_id
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if grep -qE "$pattern" "$log_path"; then
      return 0
    fi
    for process_id in "$@"; do
      if ! process_running "$process_id"; then
        echo "process $process_id exited before matching $pattern in $log_path" >&2
        return 1
      fi
    done
    sleep 1
  done
  echo "timed out waiting for $pattern in $log_path" >&2
  return 1
}

pair_once() {
  local label="$1"
  local pairing_base="$2"
  local pairing_log="$LOG_DIR/$label-pairing.log"
  local signing_log="$LOG_DIR/$label-signing.log"

  "$BIN" pairing-host \
    --product-id "$PRODUCT_ID" \
    --script "$SCRIPT" \
    --base-path "$pairing_base" \
    --auto-accept >"$pairing_log" 2>&1 &
  local pairing_pid=$!
  PAIRING_PIDS+=("$pairing_pid")
  wait_for_pattern "$pairing_log" 'polkadotapp://pair\?handshake=[[:xdigit:]]+' "$pairing_pid"
  local deeplink
  deeplink="$(grep -m1 -oE 'polkadotapp://pair\?handshake=[[:xdigit:]]+' "$pairing_log")"

  env -u HOST_CLI_SIGNER_MNEMONIC "$BIN" signing-host \
    --base-path "$SIGNER_BASE" \
    --auto-accept \
    exec "/pair $deeplink" >"$signing_log" 2>&1 &
  SIGNER_PID=$!
  wait_for_pattern "$pairing_log" '^PAIR_AND_SIGN_OK$' "$pairing_pid" "$SIGNER_PID"
  wait "$pairing_pid"
  stop_process "$SIGNER_PID"
  SIGNER_PID=""
}

pair_once "first" "$PAIRING_A_BASE"
pair_once "second" "$PAIRING_B_BASE"

env -u HOST_CLI_SIGNER_MNEMONIC "$BIN" signing-host \
  --base-path "$SIGNER_BASE" \
  exec '/devices' >"$LOG_DIR/devices.log" 2>&1
device_count="$(grep -cE '^0x[[:xdigit:]]{64}  ' "$LOG_DIR/devices.log" || true)"
[ "$device_count" -eq 2 ] || {
  echo "expected two persisted paired devices, found $device_count" >&2
  exit 1
}

env -u HOST_CLI_SIGNER_MNEMONIC "$BIN" signing-host \
  --base-path "$SIGNER_BASE" \
  --auto-accept \
  --serve >"$LOG_DIR/restarted-signing.log" 2>&1 &
SIGNER_PID=$!
wait_for_pattern "$LOG_DIR/restarted-signing.log" 'Signing host ready' "$SIGNER_PID"

FINAL_PIDS=()
for pairing_base in "$PAIRING_A_BASE" "$PAIRING_B_BASE"; do
  label="$(basename "$pairing_base")"
  "$BIN" pairing-host \
    --product-id "$PRODUCT_ID" \
    --script "$SCRIPT" \
    --base-path "$pairing_base" \
    --auto-accept >"$LOG_DIR/$label-restored.log" 2>&1 &
  process_id=$!
  PAIRING_PIDS+=("$process_id")
  FINAL_PIDS+=("$process_id")
done

deadline=$((SECONDS + TIMEOUT_SECONDS))
while [ "$SECONDS" -lt "$deadline" ]; do
  running=0
  for process_id in "${FINAL_PIDS[@]}"; do
    if process_running "$process_id"; then
      running=1
    fi
  done
  [ "$running" -eq 0 ] && break
  process_running "$SIGNER_PID" || {
    echo "restarted signing host exited while clients were running" >&2
    exit 1
  }
  sleep 1
done

for process_id in "${FINAL_PIDS[@]}"; do
  if process_running "$process_id"; then
    echo "timed out waiting for restored pairing host $process_id" >&2
    exit 1
  fi
  wait "$process_id"
done

restored_successes="$(
  { grep -l '^PAIR_AND_SIGN_OK$' "$LOG_DIR"/*-restored.log || true; } \
    | wc -l \
    | tr -d ' '
)"
[ "$restored_successes" -eq 2 ] || {
  echo "expected both restored pairing hosts to sign, found $restored_successes successes" >&2
  exit 1
}

echo "MULTI_PAIR_RESTART_OK"
