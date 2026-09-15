# Repository agent guidance

## Shared branches

- Treat every remote branch as shared unless told otherwise. Another
  contributor's commits and a reviewer's inline comments both live on it.
- Do not force push. To pick up work that landed on the base branch, merge it
  and resolve the conflicts.
- Before pushing to a branch that already exists, `git fetch origin` and look at
  the remote tip. A push whose result surprises you is a push that lost
  something.
- If a rewrite is ever approved, `--force-with-lease` alone does not protect
  the branch. It compares against the remote tracking ref, which the fetch
  above has just updated, so the lease passes for commits you never saw. Pass
  `--force-if-includes` as well, which additionally requires those commits to
  be part of what you are pushing.
- Create a backup branch before an intentional rewrite. A rewrite drops review
  context even when it preserves every commit.
- Leave unrelated local changes alone. Do not stash, reset or check out over
  work you did not create.

Two ways to lose work that involve no pushing at all:

- `git checkout -- <path>` discards uncommitted changes to that file with no
  prompt and no reflog entry to recover from.
- `git checkout <ref> -- <path>` also stages what it writes, so a later
  `git checkout -- <path>` restores from the index and hands back the version
  from `<ref>` rather than the one you expected. Undo it with
  `git restore --source=HEAD --staged --worktree <path>`.

## Rust style

- Prefer `derive_more::Display` over a handwritten `fmt::Display`
  implementation when the formatting is declarative. Use a manual
  implementation only when deriving cannot express the behavior cleanly.
