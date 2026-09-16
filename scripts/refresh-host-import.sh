#!/usr/bin/env bash
#
# Refresh a vendored host tree under hosts/<host> from the repository it was
# imported from.
#
# The trees are snapshots. Development continues upstream until a host cuts
# over, and afterwards whenever the source repository keeps a release line of
# its own, so this runs more than once per host.
#
# Two failure modes motivate every step here, and both have already happened:
#
#   Replacing the tree wholesale silently discards the adaptations that make
#   the tree work in this repository, and re-applying adaptations without
#   replacing the tree silently discards upstream's work. So the new tree is
#   taken whole and the adaptations are re-applied on top as a three-way patch.
#
#   `git add` honours this repository's ignore rules, which are not the source
#   repository's. An earlier import lost 57 files that way and nothing noticed
#   until the file hashes were compared. So files are staged with --force and
#   every path is compared against the source by blob hash.
#
# Usage:
#   scripts/refresh-host-import.sh status <host>
#   scripts/refresh-host-import.sh refresh <host> [--ref <rev>] [--source <url>]
#
# `status` reports drift without touching the tree. `refresh` rewrites
# hosts/<host> in the working tree and leaves the result staged and
# uncommitted, so the resolution of any conflict is a human decision.

set -euo pipefail

readonly MANIFEST="hosts/imports.json"

die() { echo "error: $*" >&2; exit 1; }
note() { echo "  $*"; }

repo_root() { git rev-parse --show-toplevel; }

manifest_get() {
  local host=$1 field=$2
  python3 - "$host" "$field" <<'PY'
import json, sys
host, field = sys.argv[1], sys.argv[2]
with open("hosts/imports.json") as fh:
    data = json.load(fh)
if host not in data:
    sys.exit(f"unknown host {host!r}; known: {', '.join(sorted(data))}")
print(data[host][field])
PY
}

manifest_set_ref() {
  local host=$1 ref=$2
  python3 - "$host" "$ref" <<'PY'
import json, sys
host, ref = sys.argv[1], sys.argv[2]
path = "hosts/imports.json"
with open(path) as fh:
    data = json.load(fh)
data[host]["ref"] = ref
with open(path, "w") as fh:
    json.dump(data, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY
}

# Fetch a source revision into this repository so both trees are local objects
# and can be diffed without leaving git.
fetch_source() {
  local source=$1 ref=$2
  git fetch --quiet --no-tags "$source" "$ref" 2>/dev/null \
    || git fetch --quiet --no-tags "$source" \
    || die "cannot fetch $source"
  git rev-parse --verify --quiet "${ref}^{commit}" >/dev/null \
    || die "revision $ref is not in $source"
}

# The upstream tree rewritten under hosts/<host>/, as a tree object, so a plain
# `git diff` against our own tree yields a patch that applies at the right path.
upstream_tree_at_prefix() {
  local host=$1 ref=$2 index
  index="$(mktemp)"
  GIT_INDEX_FILE="$index" git read-tree --prefix="hosts/${host}/" "${ref}^{tree}"
  GIT_INDEX_FILE="$index" git write-tree
  rm -f "$index"
}

# Every path under hosts/<host>, as "<blobhash> <path>", for the working tree
# and for the source. Comparing these is what catches a file dropped by an
# ignore rule, which a diff of tracked files cannot show.
compare_against_source() {
  local host=$1 ref=$2 adapted_list=$3
  local ours theirs rc
  ours="$(mktemp)"; theirs="$(mktemp)"

  # NUL-delimited, because git quotes and escapes any path outside ASCII and a
  # quoted path cannot have a prefix pasted onto it. One asset in the iOS tree
  # has a Cyrillic character, and with quoted output it reads as both missing
  # and extra.
  git ls-files -s -z "hosts/${host}" > "$ours"
  git ls-tree -r -z "${ref}^{tree}" > "$theirs"

  set +e
  python3 scripts/lib/compare-host-import.py "$ours" "$theirs" "$adapted_list" "hosts/${host}/"
  rc=$?
  set -e
  rm -f "$ours" "$theirs"
  return $rc
}

cmd_status() {
  local host=$1 source ref branch
  source="$(manifest_get "$host" source)"
  ref="$(manifest_get "$host" ref)"
  branch="$(manifest_get "$host" branch)"

  note "host   : hosts/${host}"
  note "source : ${source} (${branch})"
  note "at     : ${ref}"

  fetch_source "$source" "$ref"
  local tip
  tip="$(git ls-remote "$source" "refs/heads/${branch}" | cut -f1)"
  note "tip    : ${tip:-unknown}"

  if [ -n "$tip" ] && [ "$tip" != "$(git rev-parse "${ref}^{commit}")" ]; then
    fetch_source "$source" "$tip"
    note "behind by $(git rev-list --count "${ref}..${tip}" 2>/dev/null || echo '?') commits"
  else
    note "up to date"
  fi

  echo
  note "against the recorded import:"
  compare_against_source "$host" "$ref" /dev/null || true
}

cmd_refresh() {
  local host=$1; shift
  local target="" source=""
  while [ $# -gt 0 ]; do
    case $1 in
      --ref) target=$2; shift 2 ;;
      --source) source=$2; shift 2 ;;
      *) die "unknown argument $1" ;;
    esac
  done

  [ -n "$source" ] || source="$(manifest_get "$host" source)"
  local recorded branch
  recorded="$(manifest_get "$host" ref)"
  branch="$(manifest_get "$host" branch)"

  [ -z "$(git status --porcelain)" ] || die "working tree is dirty; commit or stash first"

  if [ -z "$target" ]; then
    target="$(git ls-remote "$source" "refs/heads/${branch}" | cut -f1)"
    [ -n "$target" ] || die "cannot resolve ${branch} on ${source}"
  fi

  note "refreshing hosts/${host}"
  note "from ${recorded}"
  note "to   ${target}"

  fetch_source "$source" "$recorded"
  fetch_source "$source" "$target"

  if [ "$(git rev-parse "${recorded}^{commit}")" = "$(git rev-parse "${target}^{commit}")" ]; then
    note "already at that revision, nothing to do"
    return 0
  fi

  # What this repository changed relative to the tree it imported.
  local base_tree patch
  base_tree="$(upstream_tree_at_prefix "$host" "$recorded")"
  patch="$(mktemp)"
  git diff "$base_tree" HEAD -- "hosts/${host}" > "$patch"
  local adapted_list
  adapted_list="$(mktemp)"
  git diff --name-only "$base_tree" HEAD -- "hosts/${host}" | sort > "$adapted_list"
  note "adaptations to re-apply: $(wc -l < "$adapted_list" | tr -d ' ') files"

  # Take the new tree whole, ignoring this repository's ignore rules, because
  # the source repository's committed content is what the vendored copy has to
  # reproduce.
  rm -rf "hosts/${host:?}"
  mkdir -p "hosts/${host}"
  git archive "${target}^{tree}" | tar -x -C "hosts/${host}"
  git add --all --force "hosts/${host}"

  echo
  note "re-applying adaptations"
  if git apply --3way --whitespace=nowarn "$patch"; then
    note "applied cleanly"
  else
    note "conflicts left in the working tree, resolve them before committing"
  fi
  git add --all --force "hosts/${host}" 2>/dev/null || true

  echo
  note "checking the result against the source"
  compare_against_source "$host" "$target" "$adapted_list" || true

  manifest_set_ref "$host" "$target"
  git add "$MANIFEST"
  echo
  note "recorded ${target} in ${MANIFEST}"
  note "the refresh is staged and uncommitted; review it, then commit"
  rm -f "$patch" "$adapted_list"
}

main() {
  cd "$(repo_root)"
  [ -f "$MANIFEST" ] || die "no ${MANIFEST} in this repository"
  local cmd=${1:-}; shift || true
  case "$cmd" in
    status)  [ $# -ge 1 ] || die "usage: $0 status <host>"; cmd_status "$@" ;;
    refresh) [ $# -ge 1 ] || die "usage: $0 refresh <host> [--ref <rev>]"; cmd_refresh "$@" ;;
    *) die "usage: $0 {status|refresh} <host> [options]" ;;
  esac
}

main "$@"
