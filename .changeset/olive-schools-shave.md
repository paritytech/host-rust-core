---
"@parity/truapi-host": minor
---

The test host's statement store reads the field vector the core sends, so a
topic filter matches what a product submitted, and a suite reads statements
back as decoded entries. `behaviors.resourceAllocation` withholds a named
resource, a changed permission answer reaches the core, and product storage
is readable under the name `@parity/host-api-test-sdk` gives it.

Surface a migrating suite has to match:

- `PermissionLogEntry` carries `decision` and `timestamp` as required fields,
  so an assertion comparing a whole entry names both.
- `injectStatement` answers the `StatementEntry` the store retained, and takes
  `{topics, data}` as well as the SCALE wire bytes.
- `getSubmittedStatements` answers `StatementEntry[]`, so a read of a
  statement's payload goes through `entry.data` rather than the `0x` hex.
- `fromNetworks` refuses two or more chains with no People chain among them
  when the statement store is asked for, because no declared proxy can carry
  it. Declare the People chain, or drop to a single chain.
