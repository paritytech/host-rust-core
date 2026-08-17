#!/bin/sh
# Regenerate the TrUAPIHost package build outputs in place:
#   * truapi_server.xcframework (Binaries/)
#   * uniffi-generated Swift bindings, one namespace per uniffi crate
#     (Sources/TrUAPIHost + Sources/<namespace>FFI)
#   * the bundled TS container (Sources/TrUAPIHost/Resources/truapi-container.js,
#     built from js/container/)
#
# Run after checkout and after changing the Rust core or container sources.
# Usage: ./scripts/rebuild.sh
set -eu

PACKAGE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TRUAPI_ROOT="$(cd "$PACKAGE_ROOT/../.." && pwd)"

make -C "$TRUAPI_ROOT" xcframework

# The binding copy and normalization live in sync-bindings.sh so that CI's
# --check mode and this in-place write share one definition of what the
# committed bindings should contain.
sh "$PACKAGE_ROOT/scripts/sync-bindings.sh"

# Staging the built framework lives in stage-xcframework.sh so that a caller
# wanting only that step does not need Xcode's iOS toolchain or the container
# build below.
sh "$PACKAGE_ROOT/scripts/stage-xcframework.sh"

npm --prefix "$TRUAPI_ROOT/js/container" install --no-fund --no-audit
npm --prefix "$TRUAPI_ROOT/js/container" run build:ios

echo "TrUAPIHost package outputs rebuilt in $PACKAGE_ROOT"
