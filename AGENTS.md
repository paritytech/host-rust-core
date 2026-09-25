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

## Writing for people

- Say what a thing actually is. No invented shorthands, no jargon where a plain
  word exists.
- No em dashes in prose. Use a comma or a full stop.
- Plain engineering prose: no ornate phrasing, stock transitions, inflated
  claims, or private provenance. Say directly what changed, why it matters,
  and what the reader needs to do.
- Link to the document that owns a procedure instead of copying it.

## Scope of a change

- Do not improve adjacent code, comments, or formatting unless asked. Do not
  refactor what is not broken.
- Match the conventions already in the file, even where you would have chosen
  differently.

## Comments

Doc comments on `pub` items are required, per `CLAUDE.md`. This is about the
rest.

- An inline comment is the exception, not the default. It earns its place only
  where the code cannot be made to speak for itself, and then it is brief and
  says why, never what.
- Code that is never committed is exempt: a throwaway probe, a scratch script,
  a mutation run. Anything that lands is read by people.
- Documentation explains contracts and non-obvious invariants, not a history
  of how the change was developed.

## Code is read by people and only incidentally run

- Write so a reader needs no comment to follow it. No single-character names,
  no code golf.
- Review what you just wrote and simplify it. Fewer lines is better. If a fix
  feels hacky, redo it as though you had known at the start what you know now.
  Skip this for small obvious changes; do not over-engineer.

## Types and implementation

- Do not alias primitive types. `type Counter = u64` adds another name to
  remember without preventing a counter from being confused with any other
  `u64`. Use the primitive directly, or a newtype when distinguishing values
  or enforcing construction rules provides actual type safety.
- Reuse canonical types, constants, and helpers. Do not introduce a second
  representation or a new dependency just to convert to and from the type the
  surrounding code already uses.
- Keep one source of truth. If one field already determines a fact, do not
  carry a second field describing it and add checks to keep them
  synchronized. Fix the representation.
- Add abstractions and derives for concrete needs, not possible future
  callers. Keep fields private where they protect invariants; do not add
  accessors that merely expose every implementation detail. 
- Keep dependencies in the workspace and inherit them from member crates.
- Prefer safe operations. 
- Fix the underlying cause instead of suppressing a diagnostic or adding a
  fallback that hides an error.

## Establish visibility through module hierarchy

Do not use scoped visibility modifiers such as `pub(crate)`, `pub(super)`, or
`pub(in ...)`. Structure module hierarchies properly and expose the intended
interface through focused public re-exports. Per-item modifiers require
remembering the restriction on every type and item; a proper hierarchy
establishes the boundary once. Scoped modifiers also make it easy to work
around a poorly structured module tree instead of fixing it.

Keep implementation modules private. An item can be `pub` within a private
module without exposing it outside the crate. Re-export the items that belong
to the public interface. Do not make an entire module public to expose one
helper or to make a test compile. Prefer an inherent method when an operation
belongs to an existing type rather than adding another free-standing export.

## Tests

- A test should encode why the behaviour matters, not just what the code does.
  Before changing an existing test, work out why it asserts what it asserts.
- A test that cannot fail when the logic changes is not a test. Check that it
  does.
- Prefer one `assert_eq!` over a whole value to several assertions on
  individual fields.

## Editing existing Rust

Preserve the local style. Do not add semicolons to `return`, `break` or
`continue` where the file omits them, do not add braces to match arms or
`if`/`else` written without them, and do not move operators between the end of
one line and the start of the next. Format with `cargo +nightly fmt`, and keep
it to the lines you touched.

## Rust style

- Prefer `derive_more::Display` over a handwritten `fmt::Display`
  implementation when the formatting is declarative. Use a manual
  implementation only when deriving cannot express the behavior cleanly.
