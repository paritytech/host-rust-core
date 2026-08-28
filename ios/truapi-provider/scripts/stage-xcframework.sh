#!/bin/sh
# Xcode flattens every slice's Headers into one include directory, so a
# slice-local module.modulemap collides with another xcframework's. The module
# comes from the committed Sources/truapi_providerFFI/include/module.modulemap,
# which must stay. PACKAGE_ROOT and SOURCE are overridable so this can be tested.
set -eu

PACKAGE_ROOT="${PACKAGE_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
SOURCE="${SOURCE:-$(cd "$PACKAGE_ROOT/../.." && pwd)/target/truapi_provider.xcframework}"
DEST="$PACKAGE_ROOT/Binaries/truapi_provider.xcframework"

if [ ! -d "$SOURCE" ]; then
    echo "error: $SOURCE is missing." >&2
    echo "Run 'scripts/rebuild.sh' first; this script only copies." >&2
    exit 66
fi

rm -rf "$DEST"
mkdir -p "$PACKAGE_ROOT/Binaries"
cp -R "$SOURCE" "$PACKAGE_ROOT/Binaries/"

find "$DEST" -path '*/Headers/module.modulemap' -delete

echo "XCFramework staged into $PACKAGE_ROOT/Binaries"
