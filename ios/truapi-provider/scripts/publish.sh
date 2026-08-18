#!/bin/sh
# Publish the locally built truapi_provider.xcframework as a GitHub release asset
# and point the root Package.swift at it (URL + checksum).
#
# Build first with scripts/rebuild.sh, then:
#   ./scripts/publish.sh <version>    e.g. ./scripts/publish.sh 0.1.0
#
# Tag "@parity/ios-provider@<version>", title "@parity/ios-provider <version>",
# a namespace of its own so the provider and the host release independently.
# Creates the release if the tag does not exist yet (targeting
# IOS_RELEASE_TARGET when set, or the current branch), otherwise replaces the
# asset on the existing release. Commit the resulting Package.swift change AFTER
# the upload succeeds — a manifest pushed before its asset is live breaks every
# consumer resolving in that window.
set -eu

if [ $# -ne 1 ]; then
    echo "usage: $0 <version>" >&2
    exit 64
fi

VERSION="$1"
TAG="@parity/ios-provider@${VERSION}"
TITLE="@parity/ios-provider ${VERSION}"
PACKAGE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TRUAPI_ROOT="$(cd "$PACKAGE_ROOT/../.." && pwd)"
XCFRAMEWORK="$PACKAGE_ROOT/Binaries/truapi_provider.xcframework"
BRANCH="$(git -C "$TRUAPI_ROOT" rev-parse --abbrev-ref HEAD)"
RELEASE_TARGET="${IOS_RELEASE_TARGET:-$BRANCH}"

if [ "$BRANCH" = "HEAD" ] && [ -z "${IOS_RELEASE_TARGET:-}" ]; then
    echo "error: detached HEAD — check out the branch or set IOS_RELEASE_TARGET" >&2
    exit 65
fi

if [ ! -d "$XCFRAMEWORK" ]; then
    echo "error: $XCFRAMEWORK not found — run scripts/rebuild.sh first" >&2
    exit 66
fi

# A device slice is required for anything that ships; a simulator-only build is
# for local iteration and must not become a release asset.
if [ ! -d "$XCFRAMEWORK/ios-arm64" ]; then
    echo "error: $XCFRAMEWORK has no device slice — rerun scripts/rebuild.sh without --sim-only" >&2
    exit 66
fi

if ! git -C "$TRUAPI_ROOT" diff --quiet -- Package.swift; then
    echo "error: Package.swift has uncommitted changes — commit or revert them first" >&2
    exit 65
fi

STAGING="$(mktemp -d)"
ZIP="$STAGING/truapi_provider.xcframework.zip"
trap 'rm -rf "$STAGING"' EXIT

ditto -c -k --keepParent "$XCFRAMEWORK" "$ZIP"
CHECKSUM="$(cd "$TRUAPI_ROOT" && swift package compute-checksum "$ZIP")"

if gh release view "$TAG" --repo paritytech/truapi >/dev/null 2>&1; then
    gh release upload "$TAG" "$ZIP" --repo paritytech/truapi --clobber
else
    gh release create "$TAG" "$ZIP" \
        --repo paritytech/truapi \
        --target "$RELEASE_TARGET" \
        --title "$TITLE" \
        --latest=false \
        --notes "truapi_provider.xcframework for the TrUAPIProvider Swift package."
fi

# The tag contains "@" and "/" — percent-encode it for the asset URL.
ENCODED_TAG="$(printf %s "$TAG" | sed 's/@/%40/g; s,/,%2F,g')"
URL="https://github.com/paritytech/truapi/releases/download/${ENCODED_TAG}/truapi_provider.xcframework.zip"
MANIFEST="$TRUAPI_ROOT/Package.swift"
sed -i '' -E "s|^let providerBinaryURL = .*|let providerBinaryURL = \"$URL\"|" "$MANIFEST"
sed -i '' -E "s|^let providerBinaryChecksum = .*|let providerBinaryChecksum = \"$CHECKSUM\"|" "$MANIFEST"

echo "Published $TAG ($CHECKSUM)"
echo "Package.swift updated — review and commit it."
