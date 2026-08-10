#!/usr/bin/env bash
# Regenerate the TrUAPIProvider package's build outputs from the Rust crate:
#
#   * the uniffi Swift bindings (Sources/TrUAPIProvider + Sources/truapi_providerFFI),
#     which are committed so consumers get them from a plain git checkout
#   * Binaries/truapi_provider.xcframework, which is gitignored and published as
#     a release asset by scripts/publish.sh
#
# The simulator slice alone is enough for local builds; the device slice is
# needed for anything shipped, so both are built by default. Pass --sim-only to
# skip the device slice while iterating.
set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TRUAPI_ROOT="$(cd "$PACKAGE_ROOT/../.." && pwd)"
cd "$TRUAPI_ROOT"

PROFILE="${PROFILE:-release}"
LIB=libtruapi_provider.a

SLICES=(aarch64-apple-ios-sim aarch64-apple-ios)
[ "${1:-}" = "--sim-only" ] && SLICES=(aarch64-apple-ios-sim)

CARGO_FLAGS=(-p truapi-provider --lib --no-default-features --features uniffi)
[ "$PROFILE" = release ] && CARGO_FLAGS+=(--release)

for target in "${SLICES[@]}"; do
    rustup target add "$target" >/dev/null 2>&1 || true
    echo "==> building $target ($PROFILE)"
    cargo build "${CARGO_FLAGS[@]}" --target "$target"
done

# Bindings come from the workspace bindgen so every package in this repo
# generates them the same way.
UNIFFI_OUT="$TRUAPI_ROOT/target/uniffi-provider-swift-out"
rm -rf "$UNIFFI_OUT" && mkdir -p "$UNIFFI_OUT"
echo "==> generating Swift bindings"
cargo run -q -p uniffi-bindgen-cli -- generate \
    --library "target/${SLICES[0]}/$PROFILE/$LIB" \
    --language swift \
    --out-dir "$UNIFFI_OUT"

mkdir -p "$PACKAGE_ROOT/Sources/TrUAPIProvider" \
    "$PACKAGE_ROOT/Sources/truapi_providerFFI/include"
cp "$UNIFFI_OUT/truapi_provider.swift" \
    "$PACKAGE_ROOT/Sources/TrUAPIProvider/truapi_provider.swift"
cp "$UNIFFI_OUT/truapi_providerFFI.h" \
    "$PACKAGE_ROOT/Sources/truapi_providerFFI/include/truapi_providerFFI.h"
cp "$UNIFFI_OUT/truapi_providerFFI.modulemap" \
    "$PACKAGE_ROOT/Sources/truapi_providerFFI/include/module.modulemap"

# The xcframework carries the headers; the systemLibrary target above reads the
# committed copies, so both must come from this same generation.
HEADERS="$TRUAPI_ROOT/target/uniffi-provider-headers"
rm -rf "$HEADERS" && mkdir -p "$HEADERS"
cp "$UNIFFI_OUT/truapi_providerFFI.h" "$HEADERS/"
cp "$UNIFFI_OUT/truapi_providerFFI.modulemap" "$HEADERS/module.modulemap"

OUT="$TRUAPI_ROOT/target/truapi_provider.xcframework"
rm -rf "$OUT"
ARGS=()
for target in "${SLICES[@]}"; do
    ARGS+=(-library "$TRUAPI_ROOT/target/$target/$PROFILE/$LIB" -headers "$HEADERS")
done
echo "==> packaging truapi_provider.xcframework"
xcodebuild -create-xcframework "${ARGS[@]}" -output "$OUT"

mkdir -p "$PACKAGE_ROOT/Binaries"
rm -rf "$PACKAGE_ROOT/Binaries/truapi_provider.xcframework"
cp -R "$OUT" "$PACKAGE_ROOT/Binaries/"

echo "done."
echo "Build against it with TRUAPI_USE_LOCAL_BINARY=1; publish with scripts/publish.sh."
