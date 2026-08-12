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

rm -rf "$PACKAGE_ROOT/Binaries/truapi_server.xcframework"
mkdir -p "$PACKAGE_ROOT/Binaries"
cp -R "$TRUAPI_ROOT/target/truapi_server.xcframework" "$PACKAGE_ROOT/Binaries/"

# Remove module.modulemap from each xcframework slice's Headers directory.
# Xcode's ProcessXCFramework step writes both files to the same flat DerivedData
# include directory, causing a "Multiple commands produce module.modulemap"
# collision with other xcframeworks that ship their own modulemap. Module
# resolution for truapi_serverFFI is provided by the .systemLibrary SPM target
# instead, so the modulemap inside the xcframework slice is not needed.
rm -f "$PACKAGE_ROOT/Binaries/truapi_server.xcframework/ios-arm64/Headers/module.modulemap"
rm -f "$PACKAGE_ROOT/Binaries/truapi_server.xcframework/ios-arm64-simulator/Headers/module.modulemap"

npm --prefix "$TRUAPI_ROOT/js/container" install --no-fund --no-audit
npm --prefix "$TRUAPI_ROOT/js/container" run build

echo "TrUAPIHost package outputs rebuilt in $PACKAGE_ROOT"
