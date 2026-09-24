---
title: "Product Database"
owner: "@tommyldev"
status: draft
---

# RFC — Product Database

## Summary

A host-owned SQLite database per product and account, exposed as the `Database` trait: declared tables, atomic batched writes, keyed reads, indexed scans, read-only SQL, a change feed and a replication status. Tables a product marks replicated hold the same rows on every device the account is signed in on. The host owns replication and its transport; the product declares which tables take part and how their columns merge.

## Motivation

Product state lives in `LocalStorage` and, where the webview offers it, IndexedDB. Both are per install: a message history written on Polkadot Desktop does not exist on the phone. `LocalStorage` is a flat key-value map with no listing, no batch and no atomic update, so a product that keeps a history rewrites whole JSON documents per change and maintains its own index keys. The Desktop backend applies each write as a read-modify-write of the whole product store, so concurrent writes drop each other's keys. IndexedDB is missing from some product webviews and from the QuickJS worker runtime.

t3ams (team chat over Statement Store) submits statements with a 24-hour expiry, so the device is the only durable copy of a conversation. To reach a second device it publishes an encrypted per-device membership changelog over Statement Store, re-uploads an encrypted snapshot of its whole state to Bulletin whenever the state has changed since the last upload, and restores by wiping and re-importing.

### Requirements

1. **Shared.** A row a product writes on one of the account's devices is readable by the same product on every other device of that account.
2. **Queryable.** A product reads a bounded, ordered subset of its rows without loading the rest.
3. **Atomic.** A batch of writes commits together and is durable on the device when the call returns.
4. **Observable.** A product, and its worker, learn of local and replicated changes without polling.
5. **Private.** A replicated row leaves a device only encrypted under a key the account's devices hold and no operator of the replication transport does.

## Approach

The host keeps one SQLite database per product per signed-in account. With no account signed in the product gets the anonymous database: a device-local database that never replicates.

The design has six parts:

- **Schema**: what a product declares.
- **Operations**: writes, reads and queries.
- **Changes**: how a product observes the database.
- **Replication**: what the host guarantees across devices.
- **Lifecycle**: what happens to the database around sign-in and removal.
- **Trait**: the wire surface.

### Schema

`ensure_schema` carries the product's whole schema and a schema version. The host creates missing tables, columns and indexes in one transaction and records the schema version; it never removes a table, column or index. A request whose schema version is lower than the recorded one fails with `SchemaConflict`. A column added to an existing table is nullable or carries a default. A table's primary key and sync policy are fixed once the table exists, and a changed index is a new index under a new name. `DropTable` is a write that removes the table from the recorded schema, and a later declaration creates it anew. Column names starting with `_` are reserved.

Each table declares a primary key, its indexes and a sync policy: a `LocalOnly` table's rows stay on the device that wrote them, a `Replicated` table's rows converge across the account's devices. A `Replicated` table declares no unique index. State that belongs to one device, for an entity in a `Replicated` table, goes in a `LocalOnly` table under the same primary key and is joined in `query`. Column types are SQLite's non-null storage classes plus `Json`, carried as text. A column of a `Replicated` table may name an integer column of the same table as its merge clock; a write that carries the column carries its merge clock in the same operation, and `ensure_schema` fails with `SchemaConflict` when a merge clock names a non-integer column, appears on a `LocalOnly` table, or is itself clocked by another column. A table may name text columns for full-text search; the host keeps them in the FTS5 table `<table>_fts`, tokenised as trigrams, whose `rowid` is the base table's.

### Operations

`write` applies a batch in one transaction: put a row, delete by key, delete an index range, clear a table, drop a table, or compare-and-set a row against its version. A put stores the columns it carries; columns it omits keep their stored value, or take their default, or `Null`, on a new row. A row's version is the value of a counter the host keeps per database and advances on every change, local or replicated, so a version never repeats within a database. The batch commits whole, and a batch that fails leaves the database unchanged. Every change carries the writer's timestamp: a hybrid logical clock value ordered by time and then by device.

`get` reads rows by primary key. `scan` reads a key range on the primary key or a declared index in either direction, returning a page and the position to continue after. Bounds compare in the index's sort order, a prefix of the key tuple bounds every longer tuple, `Text` compares as UTF-8 bytes and `Blob` as bytes, and a string prefix is the range from the prefix to its successor with the upper bound open. `query` runs one parameterised `SELECT` on a read-only connection that reads only the product's declared tables and their `<table>_fts` tables, and exposes each row's version as the column `_version`. The host interrupts a query that exceeds its time or row budget with `Rejected`. A cursor is a change-feed position: opaque bytes that order bytewise in change order within one database. Every write and every read returns the cursor it reflects. The trait has no rate limit: back-pressure is `Busy`, and the product retries.

### Changes

`changes_subscribe` streams every row change after a cursor and names its origin: written on this device by an executable of the product, with the tag that write carried, or arrived by replication. A subscription resumes after the cursor it is given, and a cursor older than the host retains fails it with `CursorExpired`. With no cursor the stream carries only changes made after the subscription starts. A range delete, clear or drop emits one change per row it removes on this device. A deleted row's change carries the version of its delete. A replicated change does not start a worker; a worker catches up from its stored cursor when it next runs.

`sync_status_subscribe` reports whether replication is disabled, idle, in progress or failed. An idle status carries the cursor up to which every local change is held by another device or the transport's store.

### Replication

For a `Replicated` table the host guarantees:

- Every device of the account holds the same rows once each has exchanged changes with the others.
- Concurrent writes to one row merge per column, and the rule applies to local writes as well as replicated ones. A column with a merge clock keeps the value written under the higher clock, a column without one keeps the value with the later writer's timestamp, and the writer's timestamp breaks ties. A column named as a merge clock, by itself or by another column, keeps its maximum. `Null` orders below every integer.
- A replicated value for a table or column the local schema lacks is kept and appears once `ensure_schema` declares it. A replicated row is applied without constraint checks.
- A delete, range delete, clear or drop replicates as a tombstone over its key, range or table at the writer's timestamp and is never ordered by a merge clock. A product whose deletes follow its own clock writes a column merged by that clock instead of deleting the row. A row whose write is older than a tombstone and whose values fall inside it is deleted on arrival; a put that lands after a row's delete starts a new row. The host keeps tombstones for a retention window it chooses, and a device whose last exchange predates the window rebuilds its replicated tables from another device, keeping its own writes that were never exchanged and expiring every cursor.
- A version is local to the device, so `CompareAndSet` excludes concurrent writers on one device; across devices the merge rule applies.
- Rows leave the device encrypted under a key the host derives from the account's root entropy, one key per product, as `derive_entropy` does, never under a key bound to one device. Associated data binds product, table and primary key. Table names and primary keys travel inside the ciphertext.
- Replication runs only while the account is signed in. The anonymous database and `LocalOnly` tables never replicate.
- A device over its quota stops accepting replicated rows and reports `Failed`.

The transport between devices is the host's choice. A host that has none still serves the trait and reports `Disabled`.

### Lifecycle

The trait needs no permission prompt and has no cross-product access. A host that does not implement the trait does not register it, so `ensure_schema` fails with `Unsupported`, and the product falls back to `LocalStorage`. When the signed-in account changes, including at sign-in and sign-out, every open subscription ends with `AccountChanged`, and a cursor from another database fails with `CursorExpired`. On sign-out the host keeps the account's database and stops replicating it. Rows in the anonymous database do not move into the account's database at sign-in. Removing the product from the device deletes the device's copy of every database. `reset_local` deletes every row on the device, keeps the schema, expires every cursor, and does not replicate the deletes, so `Replicated` tables refill from the account's other devices.

### Trait

Trait id 20 follows `Worker`; ids are append-only.

```rust
//! Unified [`Database`] trait.

use crate::versioned::database::{
    HostDatabaseChangesSubscribeError, HostDatabaseChangesSubscribeItem,
    HostDatabaseChangesSubscribeRequest, HostDatabaseEnsureSchemaError,
    HostDatabaseEnsureSchemaRequest, HostDatabaseEnsureSchemaResponse, HostDatabaseGetError,
    HostDatabaseGetRequest, HostDatabaseGetResponse, HostDatabaseQueryError,
    HostDatabaseQueryRequest, HostDatabaseQueryResponse, HostDatabaseResetLocalError,
    HostDatabaseResetLocalRequest, HostDatabaseResetLocalResponse, HostDatabaseScanError,
    HostDatabaseScanRequest, HostDatabaseScanResponse, HostDatabaseStatsError,
    HostDatabaseStatsRequest, HostDatabaseStatsResponse, HostDatabaseSyncStatusSubscribeError,
    HostDatabaseSyncStatusSubscribeItem, HostDatabaseSyncStatusSubscribeRequest,
    HostDatabaseWriteError, HostDatabaseWriteRequest, HostDatabaseWriteResponse,
};
use crate::{CallContext, CallError, Subscription};
use crate::{wire, wire_trait};

/// SQLite database scoped to the calling product and the signed-in account.
#[wire_trait(id = 20)]
#[crate::async_trait]
pub trait Database: Send + Sync {
    /// Declare the product's schema and create what is missing.
    ///
    /// ```ts
    /// const result = await truapi.database.ensureSchema({
    ///   schemaVersion: 1,
    ///   tables: [{
    ///     name: "messages",
    ///     columns: [
    ///       { name: "id", ty: { tag: "Text" }, nullable: false, default: undefined, mergedBy: undefined },
    ///       { name: "channel", ty: { tag: "Text" }, nullable: false, default: undefined, mergedBy: undefined },
    ///       { name: "ts", ty: { tag: "Integer" }, nullable: false, default: undefined, mergedBy: undefined },
    ///       { name: "editedAt", ty: { tag: "Integer" }, nullable: true, default: undefined, mergedBy: "editedAt" },
    ///       { name: "body", ty: { tag: "Text" }, nullable: false, default: undefined, mergedBy: "editedAt" },
    ///     ],
    ///     primaryKey: ["id"],
    ///     indexes: [{ name: "by_channel_ts", columns: [
    ///       { name: "channel", descending: false }, { name: "ts", descending: true }], unique: false }],
    ///     sync: { tag: "Replicated" },
    ///     fullText: ["body"],
    ///   }],
    /// });
    /// assert(result.isOk(), "ensureSchema failed:", result);
    /// ```
    #[wire(id = 0)]
    async fn ensure_schema(
        &self,
        _cx: &CallContext,
        _request: HostDatabaseEnsureSchemaRequest,
    ) -> Result<HostDatabaseEnsureSchemaResponse, CallError<HostDatabaseEnsureSchemaError>> {
        Err(CallError::unavailable())
    }

    /// Apply a batch of writes in one transaction.
    ///
    /// ```ts
    /// const result = await truapi.database.write({ tag: undefined, ops: [
    ///   { tag: "Put", value: { table: "messages", row: [
    ///     { column: "id", value: { tag: "Text", value: "m1" } },
    ///     { column: "channel", value: { tag: "Text", value: "c1" } },
    ///     { column: "ts", value: { tag: "Integer", value: 1700000000000n } },
    ///     { column: "editedAt", value: { tag: "Integer", value: 1700000000000n } },
    ///     { column: "body", value: { tag: "Text", value: "hello" } },
    ///   ] } },
    /// ] });
    /// assert(result.isOk(), "write failed:", result);
    /// console.log("row version:", result.value.versions[0], "cursor:", result.value.cursor);
    /// ```
    #[wire(id = 1)]
    async fn write(
        &self,
        _cx: &CallContext,
        _request: HostDatabaseWriteRequest,
    ) -> Result<HostDatabaseWriteResponse, CallError<HostDatabaseWriteError>> {
        Err(CallError::unavailable())
    }

    /// Read rows by primary key.
    ///
    /// ```ts
    /// const result = await truapi.database.get({
    ///   table: "messages",
    ///   keys: [[{ tag: "Text", value: "m1" }]],
    ///   columns: undefined,
    /// });
    /// assert(result.isOk(), "get failed:", result);
    /// console.log("row:", result.value.rows[0]);
    /// ```
    #[wire(id = 2)]
    async fn get(
        &self,
        _cx: &CallContext,
        _request: HostDatabaseGetRequest,
    ) -> Result<HostDatabaseGetResponse, CallError<HostDatabaseGetError>> {
        Err(CallError::unavailable())
    }

    /// Read a key range on the primary key or a declared index.
    ///
    /// ```ts
    /// const page = await truapi.database.scan({
    ///   table: "messages",
    ///   index: "by_channel_ts",
    ///   range: {
    ///     lower: [{ tag: "Text", value: "c1" }], upper: [{ tag: "Text", value: "c1" }],
    ///     lowerOpen: false, upperOpen: false,
    ///   },
    ///   descending: true,
    ///   limit: 100,
    ///   columns: ["id", "ts", "body"],
    ///   after: undefined,
    /// });
    /// assert(page.isOk(), "scan failed:", page);
    /// console.log("rows:", page.value.rows.length, "continue after:", page.value.nextAfter);
    /// ```
    #[wire(id = 3)]
    async fn scan(
        &self,
        _cx: &CallContext,
        _request: HostDatabaseScanRequest,
    ) -> Result<HostDatabaseScanResponse, CallError<HostDatabaseScanError>> {
        Err(CallError::unavailable())
    }

    /// Run a read-only SQL statement over the product's own tables.
    ///
    /// ```ts
    /// const result = await truapi.database.query({
    ///   sql: "SELECT m.id FROM messages m JOIN messages_fts f ON f.rowid = m.rowid " +
    ///        "WHERE messages_fts MATCH ?1 ORDER BY m.ts DESC LIMIT 50",
    ///   params: [{ tag: "Text", value: "hello" }],
    /// });
    /// assert(result.isOk(), "query failed:", result);
    /// console.log("hits:", result.value.rows);
    /// ```
    #[wire(id = 4)]
    async fn query(
        &self,
        _cx: &CallContext,
        _request: HostDatabaseQueryRequest,
    ) -> Result<HostDatabaseQueryResponse, CallError<HostDatabaseQueryError>> {
        Err(CallError::unavailable())
    }

    /// Stream row changes after a cursor.
    ///
    /// ```ts
    /// import { firstValueFrom, from } from "rxjs";
    ///
    /// const change = await firstValueFrom(
    ///   from(truapi.database.changesSubscribe({ request: { tables: ["messages"], cursor: undefined } })),
    /// );
    /// console.log(change.origin.tag, change.table, change.key);
    /// ```
    #[wire(id = 5)]
    async fn changes_subscribe(
        &self,
        _cx: &CallContext,
        _request: HostDatabaseChangesSubscribeRequest,
    ) -> Subscription<HostDatabaseChangesSubscribeItem, CallError<HostDatabaseChangesSubscribeError>>
    {
        Subscription::interrupted(CallError::unavailable())
    }

    /// Stream the replication status of the product's database.
    ///
    /// ```ts
    /// import { firstValueFrom, from } from "rxjs";
    ///
    /// const status = await firstValueFrom(from(truapi.database.syncStatusSubscribe()));
    /// console.log("sync:", status.tag);
    /// ```
    #[wire(id = 6)]
    async fn sync_status_subscribe(
        &self,
        _cx: &CallContext,
        _request: HostDatabaseSyncStatusSubscribeRequest,
    ) -> Subscription<
        HostDatabaseSyncStatusSubscribeItem,
        CallError<HostDatabaseSyncStatusSubscribeError>,
    > {
        Subscription::interrupted(CallError::unavailable())
    }

    /// Report the bytes the database occupies and the quota the host allows.
    ///
    /// ```ts
    /// const stats = await truapi.database.stats();
    /// assert(stats.isOk(), "stats failed:", stats);
    /// console.log("bytes used:", stats.value.bytesUsed, "quota:", stats.value.quota);
    /// ```
    #[wire(id = 7)]
    async fn stats(
        &self,
        _cx: &CallContext,
        _request: HostDatabaseStatsRequest,
    ) -> Result<HostDatabaseStatsResponse, CallError<HostDatabaseStatsError>> {
        Err(CallError::unavailable())
    }

    /// Delete every row on this device without replicating the deletes.
    ///
    /// ```ts
    /// const result = await truapi.database.resetLocal();
    /// assert(result.isOk(), "resetLocal failed:", result);
    /// ```
    #[wire(id = 8)]
    async fn reset_local(
        &self,
        _cx: &CallContext,
        _request: HostDatabaseResetLocalRequest,
    ) -> Result<HostDatabaseResetLocalResponse, CallError<HostDatabaseResetLocalError>> {
        Err(CallError::unavailable())
    }
}
```

Each method's error is its own `V1` envelope over `DatabaseError`; `stats` and `reset_local` use `GenericError`. `HostDatabaseSyncStatusSubscribeRequest`, `HostDatabaseStatsRequest` and `HostDatabaseResetLocalRequest` are payload-less `V1` envelopes, `HostDatabaseResetLocalResponse` is `()`, `HostDatabaseChangesSubscribeItem` wraps `DatabaseChange`, and `HostDatabaseSyncStatusSubscribeItem` wraps `DatabaseSyncStatus`. Types, derives omitted:

```rust
/// Request to declare the product's schema.
pub struct HostDatabaseEnsureSchemaRequest {
    /// Schema version; not lower than the version the host has recorded.
    pub schema_version: u32,
    /// Every table of the product.
    pub tables: Vec<DatabaseTableDef>,
}

/// Response to a schema declaration.
pub struct HostDatabaseEnsureSchemaResponse {
    /// Schema version recorded before this call, if any.
    pub previous_schema_version: Option<u32>,
}

/// A table declaration.
pub struct DatabaseTableDef {
    /// Table name, unique within the product's database.
    pub name: String,
    /// Columns in declaration order.
    pub columns: Vec<DatabaseColumnDef>,
    /// Names of the columns forming the primary key.
    pub primary_key: Vec<String>,
    /// Secondary indexes.
    pub indexes: Vec<DatabaseIndexDef>,
    /// Whether the table's rows replicate across the account's devices.
    pub sync: DatabaseSyncPolicy,
    /// Names of text columns indexed for full-text search.
    pub full_text: Vec<String>,
}

/// A column declaration.
pub struct DatabaseColumnDef {
    /// Column name, unique within the table.
    pub name: String,
    /// Storage class.
    pub ty: DatabaseColumnType,
    /// Whether `Null` is a permitted value.
    pub nullable: bool,
    /// Value an omitted column takes on a new row, and on rows that predate the column.
    pub default: Option<DatabaseValue>,
    /// Integer column of the same table whose value orders writes to this column; absent to order by the writer's timestamp.
    pub merged_by: Option<String>,
}

/// Column storage class.
pub enum DatabaseColumnType {
    /// 64-bit signed integer.
    Integer,
    /// 64-bit float.
    Real,
    /// UTF-8 text.
    Text,
    /// Raw bytes.
    Blob,
    /// UTF-8 JSON text carried as `Text`, queryable with SQLite's JSON functions.
    Json,
}

/// A secondary index declaration.
pub struct DatabaseIndexDef {
    /// Index name, unique within the table.
    pub name: String,
    /// Indexed columns in order.
    pub columns: Vec<DatabaseIndexColumn>,
    /// Whether the indexed tuple is unique; `false` on a `Replicated` table.
    pub unique: bool,
}

/// One column of an index.
pub struct DatabaseIndexColumn {
    /// Column name.
    pub name: String,
    /// Whether the column sorts descending.
    pub descending: bool,
}

/// Replication policy of a table.
pub enum DatabaseSyncPolicy {
    /// Rows stay on the device that wrote them.
    LocalOnly,
    /// Rows converge across the account's devices.
    Replicated,
}

/// A SQLite value.
pub enum DatabaseValue {
    /// SQL NULL.
    Null,
    /// 64-bit signed integer.
    Integer(i64),
    /// 64-bit float as its IEEE-754 bit pattern.
    Real(u64),
    /// UTF-8 text.
    Text(String),
    /// Raw bytes.
    Blob(Vec<u8>),
}

/// One column of a row.
pub struct DatabaseCell {
    /// Column name.
    pub column: String,
    /// Value.
    pub value: DatabaseValue,
}

/// Bounds over a primary key or index tuple.
pub struct DatabaseKeyRange {
    /// Lower bound, unbounded when absent.
    pub lower: Option<Vec<DatabaseValue>>,
    /// Upper bound, unbounded when absent.
    pub upper: Option<Vec<DatabaseValue>>,
    /// Whether the lower bound is excluded.
    pub lower_open: bool,
    /// Whether the upper bound is excluded.
    pub upper_open: bool,
}

/// One operation of a write batch.
pub enum DatabaseWriteOp {
    /// Store the carried columns of a row by primary key.
    Put {
        /// Table name.
        table: String,
        /// Columns to store; omitted columns keep their value, or take their default on a new row.
        row: Vec<DatabaseCell>,
    },
    /// Delete a row by primary key.
    Delete {
        /// Table name.
        table: String,
        /// Primary key tuple.
        key: Vec<DatabaseValue>,
    },
    /// Delete every row in a key range.
    DeleteRange {
        /// Table name.
        table: String,
        /// Index name, or the primary key when absent.
        index: Option<String>,
        /// Range to delete.
        range: DatabaseKeyRange,
    },
    /// Delete every row of a table.
    Clear {
        /// Table name.
        table: String,
    },
    /// Delete a table, its indexes and its rows.
    DropTable {
        /// Table name.
        table: String,
    },
    /// Store a row only if its version matches.
    CompareAndSet {
        /// Table name.
        table: String,
        /// Primary key tuple.
        key: Vec<DatabaseValue>,
        /// Version the row must hold, or absent when the row must not exist.
        expected: Option<u64>,
        /// Columns to store on match, as `Put` stores them.
        row: Vec<DatabaseCell>,
    },
}

/// Request to apply a write batch.
pub struct HostDatabaseWriteRequest {
    /// Operations applied in order inside one transaction.
    pub ops: Vec<DatabaseWriteOp>,
    /// Bytes echoed on every change the batch emits.
    pub tag: Option<Vec<u8>>,
}

/// Response to a write batch.
pub struct HostDatabaseWriteResponse {
    /// One entry per operation: the row's new version for `Put` and `CompareAndSet`, absent otherwise.
    pub versions: Vec<Option<u64>>,
    /// Cursor of the batch's last change.
    pub cursor: Vec<u8>,
}

/// Request to read rows by primary key.
pub struct HostDatabaseGetRequest {
    /// Table name.
    pub table: String,
    /// Primary key tuples.
    pub keys: Vec<Vec<DatabaseValue>>,
    /// Columns to return; every column when absent.
    pub columns: Option<Vec<String>>,
}

/// Response to a keyed read.
pub struct HostDatabaseGetResponse {
    /// One entry per key: the row and its version, absent when the row does not exist.
    pub rows: Vec<Option<DatabaseVersionedRow>>,
    /// Cursor this read reflects.
    pub cursor: Vec<u8>,
}

/// A row with its version.
pub struct DatabaseVersionedRow {
    /// Requested columns of the row.
    pub row: Vec<DatabaseCell>,
    /// Version of the row.
    pub version: u64,
}

/// Request to read a key range.
pub struct HostDatabaseScanRequest {
    /// Table name.
    pub table: String,
    /// Index name, or the primary key when absent.
    pub index: Option<String>,
    /// Range to read.
    pub range: DatabaseKeyRange,
    /// Whether rows return in descending key order.
    pub descending: bool,
    /// Maximum rows to return.
    pub limit: u32,
    /// Columns to return; every column when absent.
    pub columns: Option<Vec<String>>,
    /// Position from a previous response to continue after.
    pub after: Option<Vec<u8>>,
}

/// Response to a range read.
pub struct HostDatabaseScanResponse {
    /// Rows in key order, with their versions.
    pub rows: Vec<DatabaseVersionedRow>,
    /// Position to continue after, absent when the range is exhausted.
    pub next_after: Option<Vec<u8>>,
    /// Cursor this read reflects.
    pub cursor: Vec<u8>,
}

/// Request to run a read-only SQL statement.
pub struct HostDatabaseQueryRequest {
    /// A single `SELECT` with positional parameters.
    pub sql: String,
    /// Values bound to the positional parameters in order.
    pub params: Vec<DatabaseValue>,
}

/// Response to a SQL query.
pub struct HostDatabaseQueryResponse {
    /// Result column names.
    pub columns: Vec<String>,
    /// Result rows, one value per column.
    pub rows: Vec<Vec<DatabaseValue>>,
    /// Cursor this read reflects.
    pub cursor: Vec<u8>,
}

/// Request to stream row changes.
pub struct HostDatabaseChangesSubscribeRequest {
    /// Tables to observe; every table when empty.
    pub tables: Vec<String>,
    /// Cursor to resume after; only changes made after the subscription starts when absent.
    pub cursor: Option<Vec<u8>>,
}

/// One row change.
pub struct DatabaseChange {
    /// Cursor of this change.
    pub cursor: Vec<u8>,
    /// Table name.
    pub table: String,
    /// Primary key tuple of the changed row.
    pub key: Vec<DatabaseValue>,
    /// Row after the change, absent when the row was deleted.
    pub row: Option<Vec<DatabaseCell>>,
    /// Version of the row after the change, or of the delete.
    pub version: u64,
    /// Where the change came from.
    pub origin: DatabaseChangeOrigin,
}

/// Source of a row change.
pub enum DatabaseChangeOrigin {
    /// Written on this device by an executable of the product.
    Local {
        /// Tag the write batch carried.
        tag: Option<Vec<u8>>,
    },
    /// Arrived from another device of the account.
    Replicated,
}

/// Replication status of the product's database.
pub enum DatabaseSyncStatus {
    /// The host has no transport, or no account is signed in.
    Disabled,
    /// No exchange is in progress.
    Idle {
        /// Cursor up to which every local change is held by another device or the transport's store, absent when none is.
        acknowledged: Option<Vec<u8>>,
    },
    /// Changes are being exchanged.
    Syncing,
    /// The last exchange failed; the host retries and reports `Syncing` when it does.
    Failed {
        /// Human-readable failure reason.
        reason: String,
    },
}

/// Database statistics.
pub struct HostDatabaseStatsResponse {
    /// Bytes the database occupies on the device.
    pub bytes_used: u64,
    /// Bytes the host allows the product, unbounded when absent.
    pub quota: Option<u64>,
}

/// Database operation error.
pub enum DatabaseError {
    /// The declared schema conflicts with the recorded one.
    SchemaConflict {
        /// Human-readable conflict description.
        reason: String,
    },
    /// A write violated a declared constraint.
    Constraint {
        /// Human-readable violation description.
        reason: String,
    },
    /// A `CompareAndSet` found a different version.
    VersionMismatch {
        /// Index of the failing operation in the batch.
        op: u32,
        /// Version the row holds, absent when the row does not exist.
        current: Option<u64>,
    },
    /// A query was rejected by the host's statement policy or exceeded its budget.
    Rejected {
        /// Human-readable rejection reason.
        reason: String,
    },
    /// The batch exceeds the host's size limit.
    TooLarge {
        /// Largest batch the host accepts, in bytes.
        max_bytes: u64,
    },
    /// The cursor predates the retained change history or belongs to another database.
    CursorExpired,
    /// The signed-in account changed.
    AccountChanged,
    /// Storage quota exhausted.
    Full,
    /// The database is busy; retry.
    Busy,
    /// Catch-all.
    Unknown {
        /// Human-readable failure reason.
        reason: String,
    },
}
```

## Trade-offs

- Writes are structured operations, not SQL; a product that wants arbitrary DML has none. Considered and dropped: raw SQL writes with the host diffing tables after each statement.
- Per-column last-writer-wins is the only merge; state two devices edit concurrently, such as the reactions on one message, is one row per element. Considered and dropped: product-supplied merge functions.
- Rows written before sign-in stay in the anonymous database. Considered and dropped: one database per product with an account column.
- Data shared between accounts is out of scope.
- A replicated table costs more than its rows: the host keeps a timestamp per column and a tombstone per deleted row or range.
- `LocalStorage` is unchanged. Considered and dropped: replicating `LocalStorage` keys, which have no row identity to merge on.

## Open questions

- Which transport the hosts adopt for replication, and how two devices of one account find each other.
- The largest row a transport frame carries. A product that caches media of tens of megabytes may need a streamed blob call rather than a `Blob` column.
- Key rotation after a device of the account is lost.
