"""Split a vendored tree's adaptations into what stays here and what is owed upstream.

An adaptation is any path this repository changed relative to the revision it
imported. Some exist only because the tree lives here, the CI actions and the
manifests that resolve the core from this repository, and are wrong in the
source by construction. The rest is app code that the source repository does
not have, which is what a backport carries.

Reads the NUL-delimited adaptation list, the newline-delimited infrastructure
prefixes, and writes the owed paths to a file for the caller to diff.
"""

import sys


def records(path):
    with open(path, "rb") as fh:
        for record in fh.read().split(b"\0"):
            if record:
                yield record.decode("utf-8", "surrogateescape")


def is_infrastructure(relative, prefixes):
    for prefix in prefixes:
        if prefix.endswith("/"):
            if relative.startswith(prefix):
                return True
        elif relative == prefix:
            return True
    return False


def main(argv):
    adapted_path, infra_path, tree_prefix, owed_path = argv[1:5]

    with open(infra_path, encoding="utf-8") as fh:
        prefixes = [line.strip() for line in fh if line.strip()]

    stays, owed = [], []
    for path in sorted(records(adapted_path)):
        relative = path[len(tree_prefix):] if path.startswith(tree_prefix) else path
        (stays if is_infrastructure(relative, prefixes) else owed).append((path, relative))

    print(f"  stays here, infrastructure ({len(stays)})")
    for _, relative in stays:
        print(f"      {relative}")

    print()
    print(f"  owed upstream, app code ({len(owed)})")
    for _, relative in owed:
        print(f"      {relative}")

    with open(owed_path, "w", encoding="utf-8") as fh:
        for path, _ in owed:
            fh.write(path + "\n")

    if not owed:
        print()
        print("  nothing is owed upstream")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
