#!/usr/bin/env python3
"""Shellcheck the inline shell of every composite action.

actionlint reads a local `action.yml` only to validate the caller's inputs, so
a composite action's `run:` blocks never reach shellcheck the way a workflow's
do. Each one is written out as its own file here and checked directly, which is
what catches an unbalanced block that would otherwise fail at run time with no
message.
"""

import glob
import pathlib
import re
import subprocess
import sys
import tempfile

import yaml

# Expressions are interpolated before the shell ever sees them. Shellcheck
# cannot parse the braces, so they become a placeholder word that keeps the
# surrounding quoting intact.
EXPRESSION = re.compile(r"\$\{\{.*?\}\}", re.DOTALL)


def blocks():
    """Yield (label, script) for every bash `run:` in a composite action."""
    for path in sorted(glob.glob(".github/actions/*/action.yml")):
        parsed = yaml.safe_load(pathlib.Path(path).read_text()) or {}
        steps = (parsed.get("runs") or {}).get("steps") or []
        for index, step in enumerate(steps):
            if "run" not in step or step.get("shell") not in ("bash", "sh"):
                continue
            name = step.get("name", f"step {index}")
            yield f"{path} ({name})", EXPRESSION.sub("gha_expr", step["run"])


def main():
    found = list(blocks())
    if not found:
        print("no inline composite action shell to lint")
        return 0

    failed = []
    with tempfile.TemporaryDirectory() as tmp:
        for index, (label, script) in enumerate(found):
            print(f"linting {label}")
            target = pathlib.Path(tmp) / f"block{index}.sh"
            target.write_text(f"#!/usr/bin/env bash\n{script}")
            if subprocess.run(["shellcheck", str(target)]).returncode != 0:
                failed.append(label)

    for label in failed:
        print(f"::error::shellcheck reported issues in {label}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
