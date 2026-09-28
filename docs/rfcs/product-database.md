---
title: "Product Database"
owner: "@tommyldev"
status: draft
---

# RFC — Product Database

## Summary

A host-owned SQLite database per product and account, exposed as the `Database` trait: SQL statements run inside transactions the product begins, commits and rolls back, a schema version the product sets in the same commit as its migration, a change notification per commit, and limits that bound what one product can hold. The trait is shaped as a driver target, so a product uses an existing SQL library such as Drizzle or Kysely through a thin SDK adapter rather than a database library of its own. The database is local to the device. Replicating it across the account's devices is left to a follow-up RFC.

## Motivation

Product state lives in `LocalStorage` and, where the webview offers it, IndexedDB. `LocalStorage` is a flat key-value map with no listing, no batch and no atomic update, so a product that keeps a history rewrites whole JSON documents per change and maintains its own index keys. The Desktop backend applies each write as a read-modify-write of the whole product store, so concurrent writes drop each other's keys. IndexedDB is missing from some product webviews and from the QuickJS worker runtime, so a product's worker cannot share structured state with its webview.

t3ams (team chat over Statement Store) submits statements with a 24-hour expiry, so the device is the only durable copy of a conversation. It needs to page through a channel's history, search it, and record a received message together with the bookkeeping that says it was received, in one step that either happens or does not.

### Requirements

1. **Queryable.** A product reads a bounded, ordered subset of its rows without loading the rest, and joins and searches across tables.
2. **Transactional.** A product reads and writes inside one transaction that commits whole or not at all, and is durable on the device when the commit returns.
3. **Migratable.** A product changes its schema and rewrites its data in one transaction, keyed on a schema version the host stores.
4. **Observable.** A product's webview and worker learn of each other's commits without polling.
5. **Bounded.** One product cannot exhaust the device's storage or hold its database locked.

## Approach

The host keeps one SQLite database per product per signed-in account. With no account signed in the product gets the anonymous database. Rows in the anonymous database do not move into the account's database at sign-in.

The design has eight parts:

- **Transactions**: how a product runs SQL.
- **Migrations**: how a product changes its schema.
- **Changes**: how a product observes the database.
- **Limits**: what bounds one product.
- **Lifecycle**: what happens to the database around sign-in and removal.
- **Isolation**: how a host keeps one product out of another's database.
- **Developer experience**: how a product uses the database from its code.
- **Trait**: the wire surface.

### Transactions

`begin` opens a read or a write transaction and returns its id and the database's schema version. `execute` runs a list of SQL statements with positional parameters inside that transaction and returns, per statement, the result rows, the number of rows changed and the last inserted row id. `commit` makes the transaction's writes durable, `rollback` discards them. `execute` without a transaction id runs its statements in a transaction of its own that commits when the call returns, so a single write needs one call.

Each `execute` call runs inside a savepoint. A statement that fails rolls back every statement of that call and leaves the transaction open, so the product decides whether to retry, carry on or roll back. A product may open named savepoints of its own inside a transaction; the host names its per-call savepoint so a product cannot target it, and tracks which of its savepoints a product `RELEASE` of an outer one has already released. A read transaction rejects a statement that writes.

A database has at most one write transaction at a time. `begin` for a write, and `execute` without a transaction, wait for the current write transaction to end. Each executable of the product holds at most one write transaction, so a second write `begin` from the same executable fails with `Busy` at once instead of waiting on itself. A read transaction sees the database as it was at its first statement and never waits for a writer.

A transaction id is valid only for the executable that began it. The host rolls a transaction back when the product calls `rollback`, when no call on it arrives within the idle timeout, when the executable that began it ends, and when the signed-in account changes. A later call on its id fails with `TransactionClosed`.

The statement policy admits `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `REPLACE` and `WITH`; `CREATE`, `ALTER` and `DROP` of tables, indexes, views and triggers, including `CREATE VIRTUAL TABLE … USING fts5`; `SAVEPOINT`, `RELEASE` and `ROLLBACK TO` inside an open transaction; and `PRAGMA foreign_keys` and `PRAGMA defer_foreign_keys`. It rejects with `Rejected` every statement that would reach outside the product's database or around the trait: `ATTACH`, `DETACH`, every other `PRAGMA`, `VACUUM` including `VACUUM INTO`, `TEMP` objects, `BEGIN`, `COMMIT` and `ROLLBACK`, extension loading, and writes to `sqlite_` tables. Hosts ship SQLite 3.45.0 or later with FTS5 and the JSON functions, so the SQL a product writes is portable across hosts.

### Migrations

The host stores one schema version per database, starting at 0. `begin` reports it and `commit` sets it, so a migration's DDL, its data rewrite and the new version commit together or not at all. The host does not interpret the version; it only stores it.

Migrations run on the product side, with the tooling the product chooses. An ORM migrator keeps its own migrations table in the database and runs the pending steps inside one write transaction, so it needs nothing from the host beyond DDL inside a transaction; see Developer experience. A product without an ORM does the same by hand: it begins a write transaction, compares the reported version with the one its code expects, runs its steps in order and commits with the new version. A step that fails rolls the whole transaction back, leaving the database as it was. A stored version above the one the code expects means a rolled-back release, and the product refuses to open rather than downgrade.

Because only one write transaction runs at a time, a webview and a worker that open the database together do not both migrate: the second waits for the first to commit, reads the state the first left, and has nothing to do. This holds only when the check and the steps share one transaction; a migrator that reads its table before it begins can run twice. The steps ship with the product's code and change with it, and the host gains no call into product code. Considered and dropped: a host-side migration hook.

### Changes

`changes_subscribe` emits one item per committed write transaction that changed any of the tables the subscription names, or any table when it names none. The item carries the names of the tables the transaction changed and the tag its `begin` or `execute` carried, so an executable recognises its own commits. The item names tables, not rows; the product re-reads what it shows. A product that needs a row-level log writes one to a table of its own, in the same transaction as the change. When the signed-in account changes, every open subscription ends with `AccountChanged`.

### Limits

The host bounds each product, and guarantees every product at least the floors below. A host may allow more.

| Limit | Floor | When exceeded |
| --- | --- | --- |
| Database size | 64 MiB | The statement fails with `Full`; the transaction stays open, so the product can delete rows and continue. |
| Request size of one `execute` | 1 MiB | The call fails with `TooLarge` carrying the host's maximum. |
| Result size of one `execute` | 4 MiB | The call fails with `TooLarge`; the product pages with `LIMIT`. |
| Run time of one statement | 5 s | The host interrupts the statement, which fails with `Interrupted`. |
| Idle time between calls on a transaction | 10 s | The host rolls the transaction back. |
| Wait for the write transaction | 5 s | The call fails with `Busy`. |
| Open transactions per executable | 1 write, 4 read | `begin` fails with `Busy`. |

`stats` reports the bytes the database occupies and the quota. Each product has its own database, so one product's open transaction never blocks another product.

### Lifecycle

The trait needs no permission prompt and has no cross-product access. A host that does not implement the trait does not register it, so every call fails with `Unsupported`, and the product falls back to `LocalStorage`. On sign-out the host keeps the account's database. Removing the product from the device deletes every database of that product.

### Isolation

SQLite has no users, roles or schemas, so the boundary between products is the file. The rest is defence in depth around it.

- **Identity comes from the connection.** The host binds the product id to a connection when it accepts it (`ProductContext`, normalised once by `normalize_product_identifier`) and constructs that connection's `Database` service with it, as it does `PermissionsService`. No request names a database, so a product cannot ask for another product's data: there is no field in which to ask.
- **One file per product and account.** The host derives the file name the way the Desktop backend derives `LocalStorage` paths today, a readable slug of the product id plus a SHA-256 of the id, because product ids are Unicode DotNS names and are not filesystem safe. The file lives under the state root of the signed-in account, which the Desktop backend already swaps at sign-in, so the anonymous database and the account database are different files. Mobile hosts, which isolate `LocalStorage` by key prefix in one shared store, cannot do the same here: a prefix inside one SQLite file is visible through `sqlite_master` and joins. They keep a file per product inside the app sandbox. The browser host keeps the file in the origin-private file system, which is already private to the host's origin.
- **The connection cannot leave its file.** SQLite runs in the host process; the product only sends SQL text. The statement policy is enforced with `sqlite3_set_authorizer` on every connection, which decides by action code at prepare time rather than by reading SQL text, so a comment or a CTE cannot hide an `ATTACH`. Following SQLite's guidance for untrusted SQL, the host also opens each connection with `SQLITE_DBCONFIG_DEFENSIVE`, `SQLITE_DBCONFIG_TRUSTED_SCHEMA` off, extension loading off and `SQLITE_LIMIT_ATTACHED` at zero. `PRAGMA max_page_count` enforces the quota, `sqlite3_progress_handler` the statement run time, and `sqlite3_limit` the parser and expression depths.
- **Handles are scoped.** Transaction ids and subscriptions are looked up under the product and executable that created them. An id from anywhere else fails with `TransactionClosed`.
- **No cross-product path.** No query surface spans files, so cross-product access is impossible rather than forbidden. A later `database` grant would have the host attach the granting product's file on the grantee's connection, which is why `ATTACH` stays a host-only operation.

### Developer experience

A product does not write a database library. The trait is what every SQL library needs underneath: one statement with positional parameters in, positional rows with column names out, and begin, commit, rollback and savepoints on one connection. The product SDK ships that driver and thin adapters for existing libraries, and the library brings its query builder, its types and its migrator.

- `@parity/product-sdk/database` wraps the generated client the way `adaptLocalStorage` wraps `LocalStorage`: `execute`, `begin`, `commit`, `rollback` and `changes`, converting `DatabaseValue` to JavaScript values (`Real` to `number`, `Integer` to `number` when it fits and `bigint` otherwise, `Blob` to `Uint8Array`).
- `@parity/product-sdk/database/drizzle`, with `drizzle-orm` as an optional peer dependency, as `react` is today. Drizzle's `sqlite-proxy` driver takes a callback `(sql, params, method)` and expects positional rows, which `execute` returns as is. Drizzle sends `begin`, `commit`, `rollback` and `savepoint` as SQL text through that callback; the adapter maps the first three to trait calls, holds the transaction id, and serialises calls while a transaction is open, since the callback carries no connection handle. `drizzle-kit generate` works offline against the TypeScript schema and, with `driver: "expo"` or `"durable-sqlite"`, bundles the SQL into a `migrations.js` the product imports, so neither the webview nor the worker needs a filesystem. The adapter's `migrate(db, migrations)` runs the whole thing in one write transaction, which closes a race in Drizzle's own migrator, which reads its migrations table before it begins.
- `@parity/product-sdk/database/kysely`, with `kysely` optional. Kysely's `Driver` has explicit `beginTransaction`, `commitTransaction`, `rollbackTransaction` and savepoint methods, which map to the trait one to one; its SQLite query compiler, adapter and introspector are reused as is. Its `Migrator` takes a migration provider the product writes in code, and the adapter reports transactional DDL so the run is one write transaction.

```ts
import { drizzle, migrate } from "@parity/product-sdk/database/drizzle";
import { desc, eq } from "drizzle-orm";
import migrations from "./drizzle/migrations";
import * as schema from "./schema";

const db = drizzle({ schema });
await migrate(db, migrations);

const page = await db.select().from(schema.messages)
  .where(eq(schema.messages.channel, channelId))
  .orderBy(desc(schema.messages.ts))
  .limit(50);

await db.transaction(async (tx) => {
  await tx.insert(schema.messages).values(message);
  await tx.insert(schema.outbox).values({ messageId: message.id });
});
```

The statement policy admits what those libraries emit: named savepoints inside a transaction, `PRAGMA foreign_keys` and `PRAGMA defer_foreign_keys` (drizzle-kit wraps a table rebuild in them, and SQLite ignores the first inside a transaction), and reads of `sqlite_master` and the `pragma_table_info` table-valued function, which introspection uses. `drizzle-kit push` and `drizzle-kit studio` need a live connection and do not apply; the database exists only inside the host.

### Trait

Trait id 20 follows `Worker`; ids are append-only.

```rust
//! Unified [`Database`] trait.

use crate::versioned::database::{
    HostDatabaseBeginError, HostDatabaseBeginRequest, HostDatabaseBeginResponse,
    HostDatabaseChangesSubscribeError, HostDatabaseChangesSubscribeItem,
    HostDatabaseChangesSubscribeRequest, HostDatabaseCommitError, HostDatabaseCommitRequest,
    HostDatabaseCommitResponse, HostDatabaseExecuteError, HostDatabaseExecuteRequest,
    HostDatabaseExecuteResponse, HostDatabaseRollbackError, HostDatabaseRollbackRequest,
    HostDatabaseRollbackResponse, HostDatabaseStatsError, HostDatabaseStatsRequest,
    HostDatabaseStatsResponse,
};
use crate::{CallContext, CallError, Subscription};
use crate::{wire, wire_trait};

/// SQLite database scoped to the calling product and the signed-in account.
#[wire_trait(id = 20)]
#[crate::async_trait]
pub trait Database: Send + Sync {
    /// Open a read or a write transaction.
    ///
    /// ```ts
    /// const tx = await truapi.database.begin({ mode: { tag: "Write" }, tag: undefined });
    /// assert(tx.isOk(), "begin failed:", tx);
    /// console.log("transaction:", tx.value.transaction, "schema version:", tx.value.schemaVersion);
    /// ```
    #[wire(id = 0)]
    async fn begin(
        &self,
        _cx: &CallContext,
        _request: HostDatabaseBeginRequest,
    ) -> Result<HostDatabaseBeginResponse, CallError<HostDatabaseBeginError>> {
        Err(CallError::unavailable())
    }

    /// Run SQL statements inside a transaction, or in one of their own.
    ///
    /// ```ts
    /// const result = await truapi.database.execute({
    ///   transaction: undefined,
    ///   tag: undefined,
    ///   statements: [{
    ///     sql: "SELECT id, body FROM messages WHERE channel = ?1 ORDER BY ts DESC LIMIT 50",
    ///     params: [{ tag: "Text", value: "c1" }],
    ///   }],
    /// });
    /// assert(result.isOk(), "execute failed:", result);
    /// console.log("rows:", result.value.results[0].rows);
    /// ```
    #[wire(id = 1)]
    async fn execute(
        &self,
        _cx: &CallContext,
        _request: HostDatabaseExecuteRequest,
    ) -> Result<HostDatabaseExecuteResponse, CallError<HostDatabaseExecuteError>> {
        Err(CallError::unavailable())
    }

    /// Commit a transaction, optionally setting the schema version.
    ///
    /// ```ts
    /// const result = await truapi.database.commit({ transaction: 1n, schemaVersion: undefined });
    /// assert(result.isOk(), "commit failed:", result);
    /// ```
    #[wire(id = 2)]
    async fn commit(
        &self,
        _cx: &CallContext,
        _request: HostDatabaseCommitRequest,
    ) -> Result<HostDatabaseCommitResponse, CallError<HostDatabaseCommitError>> {
        Err(CallError::unavailable())
    }

    /// Discard a transaction's writes.
    ///
    /// ```ts
    /// const result = await truapi.database.rollback({ transaction: 1n });
    /// assert(result.isOk(), "rollback failed:", result);
    /// ```
    #[wire(id = 3)]
    async fn rollback(
        &self,
        _cx: &CallContext,
        _request: HostDatabaseRollbackRequest,
    ) -> Result<HostDatabaseRollbackResponse, CallError<HostDatabaseRollbackError>> {
        Err(CallError::unavailable())
    }

    /// Stream one item per committed write transaction.
    ///
    /// ```ts
    /// import { firstValueFrom, from } from "rxjs";
    ///
    /// const change = await firstValueFrom(
    ///   from(truapi.database.changesSubscribe({ request: { tables: ["messages"] } })),
    /// );
    /// console.log("changed:", change.tables, "tag:", change.tag);
    /// ```
    #[wire(id = 4)]
    async fn changes_subscribe(
        &self,
        _cx: &CallContext,
        _request: HostDatabaseChangesSubscribeRequest,
    ) -> Subscription<HostDatabaseChangesSubscribeItem, CallError<HostDatabaseChangesSubscribeError>>
    {
        Subscription::interrupted(CallError::unavailable())
    }

    /// Report the bytes the database occupies and the quota the host allows.
    ///
    /// ```ts
    /// const stats = await truapi.database.stats();
    /// assert(stats.isOk(), "stats failed:", stats);
    /// console.log("bytes used:", stats.value.bytesUsed, "quota:", stats.value.quota);
    /// ```
    #[wire(id = 5)]
    async fn stats(
        &self,
        _cx: &CallContext,
        _request: HostDatabaseStatsRequest,
    ) -> Result<HostDatabaseStatsResponse, CallError<HostDatabaseStatsError>> {
        Err(CallError::unavailable())
    }
}
```

Each method's error is its own `V1` envelope over `DatabaseError`; `stats` uses `GenericError`. `HostDatabaseStatsRequest` is a payload-less `V1` envelope, `HostDatabaseCommitResponse` and `HostDatabaseRollbackResponse` are `()`, and `HostDatabaseChangesSubscribeItem` wraps `DatabaseChange`. Types, derives omitted:

```rust
/// Request to open a transaction.
pub struct HostDatabaseBeginRequest {
    /// Whether the transaction may write.
    pub mode: DatabaseTransactionMode,
    /// Bytes echoed on the change item the transaction's commit emits.
    pub tag: Option<Vec<u8>>,
}

/// Kind of transaction.
pub enum DatabaseTransactionMode {
    /// Reads a snapshot and never waits for a writer.
    Read,
    /// Holds the database's single write transaction.
    Write,
}

/// Response to opening a transaction.
pub struct HostDatabaseBeginResponse {
    /// Transaction id, valid for the executable that began it.
    pub transaction: u64,
    /// Schema version the database holds, 0 when never set.
    pub schema_version: u32,
}

/// Request to run SQL statements.
pub struct HostDatabaseExecuteRequest {
    /// Transaction to run in, or absent to run in a transaction of their own that commits on return.
    pub transaction: Option<u64>,
    /// Bytes echoed on the change item, used only when `transaction` is absent.
    pub tag: Option<Vec<u8>>,
    /// Statements run in order inside one savepoint.
    pub statements: Vec<DatabaseStatement>,
}

/// One SQL statement.
pub struct DatabaseStatement {
    /// A single statement with positional parameters.
    pub sql: String,
    /// Values bound to the positional parameters in order.
    pub params: Vec<DatabaseValue>,
}

/// Response to running SQL statements.
pub struct HostDatabaseExecuteResponse {
    /// One result per statement, in order.
    pub results: Vec<DatabaseStatementResult>,
}

/// Result of one statement.
pub struct DatabaseStatementResult {
    /// Result column names, empty for a statement that returns no rows.
    pub columns: Vec<String>,
    /// Result rows, one value per column.
    pub rows: Vec<Vec<DatabaseValue>>,
    /// Rows the statement inserted, updated or deleted.
    pub rows_changed: u64,
    /// Row id of the last row the statement inserted, absent when it inserted none.
    pub last_insert_rowid: Option<i64>,
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

/// Request to commit a transaction.
pub struct HostDatabaseCommitRequest {
    /// Transaction to commit.
    pub transaction: u64,
    /// Schema version to store with the commit, or absent to keep the stored one.
    pub schema_version: Option<u32>,
}

/// Request to roll a transaction back.
pub struct HostDatabaseRollbackRequest {
    /// Transaction to roll back.
    pub transaction: u64,
}

/// Request to stream committed changes.
pub struct HostDatabaseChangesSubscribeRequest {
    /// Tables to observe; every table when empty.
    pub tables: Vec<String>,
}

/// One committed write transaction.
pub struct DatabaseChange {
    /// Tables the transaction changed.
    pub tables: Vec<String>,
    /// Tag the transaction carried.
    pub tag: Option<Vec<u8>>,
}

/// Database statistics.
pub struct HostDatabaseStatsResponse {
    /// Bytes the database occupies on the device.
    pub bytes_used: u64,
    /// Bytes the host allows the database.
    pub quota: u64,
}

/// Database operation error.
pub enum DatabaseError {
    /// SQLite rejected the statement, for example a syntax error or an unknown table.
    Sql {
        /// Index of the failing statement in the call.
        statement: u32,
        /// SQLite's error message.
        reason: String,
    },
    /// A statement violated a constraint.
    Constraint {
        /// Index of the failing statement in the call.
        statement: u32,
        /// SQLite's error message.
        reason: String,
    },
    /// The statement policy refused the statement, or a read transaction ran a write.
    Rejected {
        /// Index of the refused statement in the call.
        statement: u32,
        /// Human-readable rejection reason.
        reason: String,
    },
    /// The host interrupted a statement that exceeded its run time.
    Interrupted {
        /// Index of the interrupted statement in the call.
        statement: u32,
    },
    /// The request or its result exceeds the host's size limit.
    TooLarge {
        /// Largest size the host accepts, in bytes.
        max_bytes: u64,
    },
    /// The database reached its quota.
    Full,
    /// The write transaction stayed taken past the wait limit, or the executable holds its maximum of open transactions.
    Busy,
    /// The transaction was rolled back or committed, or belongs to another executable.
    TransactionClosed,
    /// The signed-in account changed.
    AccountChanged,
    /// Catch-all.
    Unknown {
        /// Human-readable failure reason.
        reason: String,
    },
}
```

## Trade-offs

- The database does not replicate across the account's devices; a follow-up RFC covers replication, its transport and its keys. The database is already per account so that RFC has a unit to replicate, and it will need the host to capture row changes from arbitrary SQL, which SQLite's session extension provides.
- An open write transaction holds the database across round trips between the product and the host. The idle timeout, the single write transaction per executable and the per-product database bound the cost. Considered and dropped: atomic batches of structured writes with compare-and-set, which cannot check rows they do not write and cannot run a migration atomically.
- The SQLite dialect and its minimum version become part of the contract. Considered and dropped: structured write operations, which cannot express `UPDATE … WHERE`, increments or `INSERT … SELECT`.
- Migrations live on the product side, in the library's migrator or the product's own code; the host only stores a version. Considered and dropped: a declarative schema the host diffs, which only adds tables and columns and cannot rewrite data; and a host-side migration hook, which needs the host to call into product code.
- The SDK ships drivers for existing libraries, not a query builder or ORM of its own. Those libraries' SQLite dialects assume one connection per database, which the single write transaction per executable matches.
- Isolation rests on a file per product and the SQLite authorizer, not on cryptography. A product's data is as private as the host's own storage, which is the guarantee `LocalStorage` gives today.
- Change notifications name tables, not rows. Considered and dropped: a row-level change feed with resumable cursors, which needs a change log the host retains.
- `LocalStorage` is unchanged.

## Open questions

- Whether a product can ask for more than the quota floor, and whether the user approves it.
- The largest row a transport frame carries. A product that caches media of tens of megabytes may need a streamed blob call rather than a `Blob` column.
- How the browser host persists a SQLite database.
- Whether the host enables foreign key enforcement. drizzle-kit rebuilds a table by creating a new one, copying the rows, dropping the old one and renaming, inside a transaction where `PRAGMA foreign_keys=OFF` has no effect, so with enforcement on the drop of a referenced table runs enforced.
