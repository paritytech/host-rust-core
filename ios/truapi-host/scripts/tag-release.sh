#!/bin/sh
# Create the tag a SwiftPM consumer resolves.
#
# SwiftPM resolves a package's source targets from the git checkout and has no
# way to fetch them from a release asset, so a branch that git-ignores the
# generated bindings cannot be consumed directly. The tag commit carries them:
# the manifest pointing at the published xcframework, plus every source path
# Package.swift declares.
#
# Usage: ./scripts/tag-release.sh <version>
#
# Expects the generated outputs to be present already: rebuild.sh for the host,
# scripts/sync-bindings.sh under ios/truapi-provider for the provider, and the
# js/container build for the lockdown resource. Creates the commit and tag
# locally; pushing is the caller's decision.
set -eu

if [ $# -ne 1 ]; then
    echo "usage: $0 <version>" >&2
    exit 64
fi

VERSION="$1"
TRUAPI_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$TRUAPI_ROOT"

if git rev-parse -q --verify "refs/tags/${VERSION}" >/dev/null 2>&1; then
    echo "error: tag ${VERSION} already exists" >&2
    exit 65
fi

# Read the paths out of the manifest rather than repeating them, so this cannot
# drift from what SwiftPM will look for. Binaries/ is excluded: only the
# useLocalBinary branch names it, and a published manifest never takes that
# branch.
manifest_paths() {
    sed -n -E 's/^[[:space:]]*path: "([^"]+)".*/\1/p' Package.swift | grep -v '/Binaries/'
}

if ! grep -q '^let useLocalBinary = ProcessInfo' Package.swift; then
    echo "error: Package.swift does not read TRUAPI_USE_LOCAL_BINARY from the environment;" >&2
    echo "a published manifest must never pin the local binary." >&2
    exit 65
fi

missing=""
for path in $(manifest_paths); do
    [ -e "${path}" ] || missing="${missing} ${path}"
done
if [ -n "${missing}" ]; then
    echo "error: Package.swift declares paths that do not exist:${missing}" >&2
    echo "Generate them first (ios/truapi-host/scripts/rebuild.sh," >&2
    echo "ios/truapi-provider/scripts/sync-bindings.sh, npm -w js/container run build)." >&2
    exit 66
fi

for path in $(manifest_paths); do
    git add --force -- "${path}"
done
git add -- Package.swift

# The xcframework ships as a release asset. Tagging one into git would add
# tens of megabytes to every consumer's clone.
if git diff --cached --name-only | grep -q '/Binaries/'; then
    echo "error: refusing to tag an xcframework into git" >&2
    exit 65
fi

git commit -q -m "release(ios): TrUAPIHost ${VERSION}"
git tag "${VERSION}"

echo "Tagged ${VERSION} at $(git rev-parse --short HEAD) with $(git ls-tree -r --name-only HEAD -- ios | wc -l | tr -d ' ') files under ios/"
