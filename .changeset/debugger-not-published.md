---
"@parity/truapi-debugger": patch
---

The debugger is marked private, which is what it already was in practice: it has
never been published, and its README runs it from the workspace. Changesets
bumped its version with every release because it depends on the client, so the
version it declared climbed while nothing shipped, and the registry drift check
reported a published version that was missing. Publishing it later is removing
that one field.
