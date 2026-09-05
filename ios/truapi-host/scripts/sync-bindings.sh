#!/bin/sh
# Copy the uniffi-generated Swift bindings from target/uniffi-swift-out into the
# TrUAPIHost package, normalizing them the way the committed files are stored.
#
# Requires `make uniffi` (or `make xcframework`, which depends on it) to have run
# first; this script generates nothing itself.
#
# Usage:
#   ./scripts/sync-bindings.sh            write the bindings in place
#   ./scripts/sync-bindings.sh --check    report stale committed bindings, write nothing
set -eu

PACKAGE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TRUAPI_ROOT="$(cd "$PACKAGE_ROOT/../.." && pwd)"
UNIFFI_OUT="$TRUAPI_ROOT/target/uniffi-swift-out"

NAMESPACES="truapi truapi_platform truapi_server pvm_runtime"

CHECK_ONLY=0
case "${1-}" in
    --check) CHECK_ONLY=1 ;;
    "") ;;
    *)
        echo "usage: $0 [--check]" >&2
        exit 2
        ;;
esac

if [ ! -d "$UNIFFI_OUT" ]; then
    echo "error: $UNIFFI_OUT is missing." >&2
    echo "Run 'make uniffi' at the repo root first; this script only copies." >&2
    exit 66
fi

# Stage into $1 (a directory root laid out like the package), so that --check
# never touches the working tree and an interrupted write cannot leave half of a
# namespace synced.
stage_bindings() {
    dest="$1"
    for namespace in $NAMESPACES; do
        mkdir -p "$dest/Sources/TrUAPIHost" "$dest/Sources/${namespace}FFI/include"
        cp "$UNIFFI_OUT/${namespace}.swift" \
            "$dest/Sources/TrUAPIHost/${namespace}.swift"
        cp "$UNIFFI_OUT/${namespace}FFI.h" \
            "$dest/Sources/${namespace}FFI/include/${namespace}FFI.h"
        cp "$UNIFFI_OUT/${namespace}FFI.modulemap" \
            "$dest/Sources/${namespace}FFI/include/module.modulemap"
        # UniFFI templates emit trailing spaces around optional fragments. Keep the
        # committed bindings stable so rebuilding only records API changes.
        perl -pi -e 's/[ \t]+$//' \
            "$dest/Sources/TrUAPIHost/${namespace}.swift" \
            "$dest/Sources/${namespace}FFI/include/${namespace}FFI.h" \
            "$dest/Sources/${namespace}FFI/include/module.modulemap"
    done
}

relative_paths() {
    for namespace in $NAMESPACES; do
        echo "Sources/TrUAPIHost/${namespace}.swift"
        echo "Sources/${namespace}FFI/include/${namespace}FFI.h"
        echo "Sources/${namespace}FFI/include/module.modulemap"
    done
}

if [ "$CHECK_ONLY" -eq 0 ]; then
    stage_bindings "$PACKAGE_ROOT"
    echo "Bindings synced into $PACKAGE_ROOT/Sources"
    exit 0
fi

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
stage_bindings "$STAGING"

stale=0
# Report every stale file rather than stopping at the first: a HostCallbacks
# change usually touches all three namespaces, and one-at-a-time reporting
# invites partial fixes.
for path in $(relative_paths); do
    if ! diff -u "$PACKAGE_ROOT/$path" "$STAGING/$path" \
        --label "committed/$path" --label "generated/$path"; then
        stale=$((stale + 1))
    fi
done

if [ "$stale" -ne 0 ]; then
    cat >&2 <<'EOF'

error: the committed iOS bindings do not match the current Rust surface.

Regenerate and commit them:

    make uniffi && ./ios/truapi-host/scripts/sync-bindings.sh

Regenerating alone is usually not enough: the hand-written conformers
(ios/truapi-host/Sources/TrUAPIHost/TrUAPIHost.swift and
android/truapi-host/.../TrUAPIHost.kt) need a matching change whenever
HostCallbacks gains or changes a requirement.
EOF
    exit 1
fi

echo "Committed iOS bindings are current."
