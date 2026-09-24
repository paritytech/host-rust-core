//! Core-owned SQLite store: one writer connection, a small read-only pool,
//! and async access that works on any executor.
//!
//! Each connection runs on its own thread (via `async-sqlite`), so SQLite work
//! never blocks the runtime's executor.

use std::path::{Path, PathBuf};

use async_sqlite::{JournalMode, Pool, PoolBuilder};
use rusqlite::{OpenFlags, TransactionBehavior};
use rusqlite_migration::Migrations;

/// Where a database lives.
#[derive(Debug, Clone)]
pub enum DbLocation {
    /// A file. Its directory must exist.
    File(PathBuf),
    /// A private in-memory database, for tests.
    Memory,
}

/// Options for [`Db::open`].
#[derive(Debug, Clone)]
pub struct DbConfig {
    /// Where the database lives.
    pub location: DbLocation,
    /// Builds the schema migrations, applied in order on the writer before
    /// `open` returns.
    pub migrations: fn() -> Migrations<'static>,
    /// Number of read-only connections. A [`DbLocation::Memory`] database
    /// reads through the writer instead.
    pub readers: usize,
}

/// File name of the core database inside the host-configured directory.
pub const CORE_DB_FILE: &str = "core.sqlite3";

/// Read-only connections opened for the core database.
const CORE_DB_READERS: usize = 2;

/// Schema of the core database, one migration per change, in order.
pub fn core_migrations() -> Migrations<'static> {
    Migrations::new(Vec::new())
}

/// The core database configuration for a host-provided directory.
pub fn core_db_config(directory: &Path) -> DbConfig {
    DbConfig {
        location: DbLocation::File(directory.join(CORE_DB_FILE)),
        migrations: core_migrations,
        readers: CORE_DB_READERS,
    }
}

/// Why a store operation failed.
#[derive(Debug, thiserror::Error)]
pub enum DbError {
    /// The database could not be opened or configured.
    #[error("database open failed: {0}")]
    Open(String),
    /// A migration failed. The schema stays at its previous version.
    #[error("database migration failed: {0}")]
    Migration(String),
    /// SQLite reported an error.
    #[error(transparent)]
    Sqlite(#[from] rusqlite::Error),
    /// A connection worker failed outside SQLite.
    #[error("database connection failed: {0}")]
    Connection(String),
    /// The database was closed.
    #[error("database closed")]
    Closed,
    /// The host configured no database location.
    #[error("no database configured")]
    NotConfigured,
}

impl From<async_sqlite::Error> for DbError {
    fn from(error: async_sqlite::Error) -> Self {
        match error {
            async_sqlite::Error::Closed => Self::Closed,
            async_sqlite::Error::Rusqlite(error) => Self::Sqlite(error),
            other => Self::Connection(other.to_string()),
        }
    }
}

/// What a database reports about itself.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct DbStatus {
    /// Version of the SQLite library serving the database.
    pub sqlite_version: String,
    /// Number of migrations applied (`PRAGMA user_version`).
    pub schema_version: u32,
    /// Absolute file path, or `None` for an in-memory database.
    pub path: Option<String>,
}

/// A handle to one SQLite database. Cloning shares the same connections.
#[derive(Clone)]
pub struct Db {
    writer: Pool,
    readers: Pool,
}

impl Db {
    /// Opens or creates the database, applies the connection settings and runs
    /// pending migrations on the writer.
    pub async fn open(config: DbConfig) -> Result<Self, DbError> {
        let writer = match &config.location {
            DbLocation::File(path) => PoolBuilder::new().path(path).journal_mode(JournalMode::Wal),
            DbLocation::Memory => PoolBuilder::new(),
        }
        .num_conns(1)
        .open()
        .await
        .map_err(|error| DbError::Open(error.to_string()))?;

        let migrations = config.migrations;
        writer
            .conn_mut_and_then(move |conn| {
                conn.pragma_update(None, "synchronous", "FULL")?;
                conn.pragma_update(None, "foreign_keys", true)?;
                conn.pragma_update(None, "temp_store", "MEMORY")?;
                conn.busy_timeout(BUSY_TIMEOUT)?;
                apply_migrations(conn, migrations)
            })
            .await?;

        let readers = match &config.location {
            DbLocation::File(path) => {
                let readers = PoolBuilder::new()
                    .path(path)
                    .flags(OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX)
                    .num_conns(config.readers)
                    .open()
                    .await
                    .map_err(|error| DbError::Open(error.to_string()))?;
                readers
                    .conn_for_each(|conn| conn.busy_timeout(BUSY_TIMEOUT))
                    .await
                    .into_iter()
                    .collect::<Result<Vec<()>, _>>()?;
                readers
            }
            DbLocation::Memory => writer.clone(),
        };

        Ok(Self { writer, readers })
    }

    /// Runs `f` in one `BEGIN IMMEDIATE` transaction on the writer. Commits
    /// when `f` returns `Ok` and rolls back when it returns `Err`.
    pub async fn write<T, F>(&self, f: F) -> Result<T, DbError>
    where
        F: FnOnce(&rusqlite::Transaction<'_>) -> Result<T, DbError> + Send + 'static,
        T: Send + 'static,
    {
        self.writer
            .conn_mut_and_then(move |conn| {
                let tx = conn.transaction_with_behavior(TransactionBehavior::Immediate)?;
                let value = f(&tx)?;
                tx.commit()?;
                Ok(value)
            })
            .await
    }

    /// Runs `f` on a read-only connection that sees the last committed state.
    pub async fn read<T, F>(&self, f: F) -> Result<T, DbError>
    where
        F: FnOnce(&rusqlite::Connection) -> Result<T, DbError> + Send + 'static,
        T: Send + 'static,
    {
        self.readers.conn_and_then(f).await
    }

    /// Reports the SQLite version, schema version and file path.
    pub async fn status(&self) -> Result<DbStatus, DbError> {
        self.read(|conn| {
            Ok(DbStatus {
                sqlite_version: rusqlite::version().to_owned(),
                schema_version: conn.pragma_query_value(None, "user_version", |row| row.get(0))?,
                path: conn
                    .path()
                    .filter(|path| !path.is_empty())
                    .map(str::to_owned),
            })
        })
        .await
    }

    /// Checkpoints the write-ahead log and closes every connection.
    pub async fn close(&self) -> Result<(), DbError> {
        self.writer
            .conn(|conn| conn.query_row("PRAGMA wal_checkpoint(TRUNCATE)", [], |_| Ok(())))
            .await?;
        self.readers.close().await?;
        self.writer.close().await?;
        Ok(())
    }
}

/// Brings `conn` to the latest schema. An empty migration list is a schema
/// with no tables yet, not an error.
fn apply_migrations(
    conn: &mut rusqlite::Connection,
    migrations: fn() -> Migrations<'static>,
) -> Result<(), DbError> {
    match migrations().to_latest(conn) {
        Ok(())
        | Err(rusqlite_migration::Error::MigrationDefinition(
            rusqlite_migration::MigrationDefinitionError::NoMigrationsDefined,
        )) => Ok(()),
        Err(error) => Err(DbError::Migration(error.to_string())),
    }
}

/// One statement a `#[dao]` runs, as listed in its `QUERIES`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DaoStatement {
    /// The SQL text.
    pub sql: &'static str,
    /// Whether it comes from a `#[query]`, which runs on a read-only
    /// connection and so must not write.
    pub read_only: bool,
}

/// Deserializes one row for code that `#[dao]` generates. A value that does
/// not fit its field is reported with the column index and SQLite type it
/// actually has.
#[doc(hidden)]
pub fn dao_row<T: serde::de::DeserializeOwned>(row: &rusqlite::Row<'_>) -> rusqlite::Result<T> {
    // serde_rusqlite indexes past the last column when a tuple is wider than
    // the row, which panics instead of returning an error.
    let decoded = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        serde_rusqlite::from_row(row)
    }))
    .map_err(|_| {
        rusqlite::Error::FromSqlConversionFailure(
            row.as_ref().column_count(),
            rusqlite::types::Type::Null,
            "the row has fewer columns than the type it is read into".into(),
        )
    })?;
    decoded.map_err(|error| {
        let column = match &error {
            serde_rusqlite::Error::Rusqlite(_) => None,
            serde_rusqlite::Error::Deserialization {
                column: Some(name), ..
            } => row.as_ref().column_index(name).ok(),
            _ => Some(0),
        };
        match (error, column) {
            (serde_rusqlite::Error::Rusqlite(error), _) => error,
            (error, column) => {
                let column = column.unwrap_or(0);
                let found = row
                    .get_ref(column)
                    .map(|value| value.data_type())
                    .unwrap_or(rusqlite::types::Type::Null);
                rusqlite::Error::FromSqlConversionFailure(column, found, Box::new(error))
            }
        }
    })
}

/// Prepares every statement against an in-memory database migrated to the
/// latest schema, and checks that each `#[query]` statement only reads.
/// Returns the first statement that fails, with the reason.
#[cfg(test)]
pub(crate) fn prepare_all(
    migrations: fn() -> Migrations<'static>,
    statements: &[DaoStatement],
) -> Result<(), (String, String)> {
    let mut conn = rusqlite::Connection::open_in_memory()
        .map_err(|error| (String::new(), error.to_string()))?;
    apply_migrations(&mut conn, migrations).map_err(|error| (String::new(), error.to_string()))?;
    for statement in statements {
        let failure = |reason: String| (statement.sql.to_owned(), reason);
        let prepared = conn
            .prepare(statement.sql)
            .map_err(|error| failure(error.to_string()))?;
        if statement.read_only && !prepared.readonly() {
            return Err(failure(
                "a #[query] runs on a read-only connection but this statement writes; use \
                 #[execute]"
                    .to_owned(),
            ));
        }
    }
    Ok(())
}

const BUSY_TIMEOUT: core::time::Duration = core::time::Duration::from_secs(5);

/// Opens a [`Db`] on first use and hands out the same handle afterwards.
pub struct LazyDb {
    config: DbConfig,
    db: futures::lock::Mutex<Option<Db>>,
}

impl LazyDb {
    /// Wraps `config` without touching the file.
    pub fn new(config: DbConfig) -> Self {
        Self {
            config,
            db: futures::lock::Mutex::new(None),
        }
    }

    /// Returns the open database, opening it and running migrations if
    /// needed. A failed open is not cached, so the next call retries.
    pub async fn get(&self) -> Result<Db, DbError> {
        let mut slot = self.db.lock().await;
        if let Some(db) = slot.as_ref() {
            return Ok(db.clone());
        }
        let db = Db::open(self.config.clone()).await?;
        *slot = Some(db.clone());
        Ok(db)
    }
}

#[cfg(test)]
mod dao_tests;

#[cfg(test)]
mod tests {
    use futures::executor::block_on;
    use rusqlite::OptionalExtension;
    use rusqlite_migration::M;

    use super::*;

    fn migrations() -> Migrations<'static> {
        Migrations::new(vec![
            M::up("CREATE TABLE ledger (id INTEGER PRIMARY KEY, note TEXT NOT NULL)"),
            M::up("ALTER TABLE ledger ADD COLUMN amount INTEGER NOT NULL DEFAULT 0"),
        ])
    }

    fn file_config(dir: &tempfile::TempDir) -> DbConfig {
        DbConfig {
            location: DbLocation::File(dir.path().join("core.sqlite3")),
            migrations,
            readers: 2,
        }
    }

    fn memory_config() -> DbConfig {
        DbConfig {
            location: DbLocation::Memory,
            migrations,
            readers: 2,
        }
    }

    fn insert(db: &Db, note: &'static str) -> Result<(), DbError> {
        block_on(db.write(move |tx| {
            tx.execute("INSERT INTO ledger (note) VALUES (?1)", [note])?;
            Ok(())
        }))
    }

    fn notes(db: &Db) -> Vec<String> {
        block_on(db.read(|conn| {
            let mut stmt = conn.prepare("SELECT note FROM ledger ORDER BY id")?;
            let rows = stmt.query_map([], |row| row.get(0))?;
            Ok(rows.collect::<Result<Vec<String>, _>>()?)
        }))
        .unwrap()
    }

    #[test]
    fn readers_see_what_the_writer_committed() {
        // Durable callers write on the writer and read back through the pool;
        // a commit that the pool cannot see would make recovery act on stale state.
        let dir = tempfile::tempdir().unwrap();
        let db = block_on(Db::open(file_config(&dir))).unwrap();

        insert(&db, "first").unwrap();
        insert(&db, "second").unwrap();

        assert_eq!(notes(&db), vec!["first".to_owned(), "second".to_owned()]);
    }

    #[test]
    fn a_failing_write_leaves_nothing_behind() {
        // Domain rows and ledger rows are registered in one write; a partial
        // commit would leave a transaction without the state it consumes.
        let db = block_on(Db::open(memory_config())).unwrap();

        let result = block_on(db.write(|tx| {
            tx.execute("INSERT INTO ledger (note) VALUES ('orphan')", [])?;
            Err::<(), _>(DbError::Connection("caller gave up".into()))
        }));

        assert!(matches!(result, Err(DbError::Connection(_))));
        assert_eq!(notes(&db), Vec::<String>::new());
    }

    #[test]
    fn migrations_run_once_and_survive_reopening() {
        // Reopening an existing file must not re-run migrations or lose rows.
        let dir = tempfile::tempdir().unwrap();
        let db = block_on(Db::open(file_config(&dir))).unwrap();
        insert(&db, "kept").unwrap();
        block_on(db.close()).unwrap();

        let reopened = block_on(Db::open(file_config(&dir))).unwrap();
        let schema_version: u32 = block_on(
            reopened
                .read(|conn| Ok(conn.pragma_query_value(None, "user_version", |row| row.get(0))?)),
        )
        .unwrap();

        assert_eq!(
            (schema_version, notes(&reopened)),
            (2, vec!["kept".to_owned()])
        );
    }

    #[test]
    fn readers_cannot_write() {
        // A read that silently wrote would bypass the single writer and its
        // transaction boundaries.
        let dir = tempfile::tempdir().unwrap();
        let db = block_on(Db::open(file_config(&dir))).unwrap();

        let result = block_on(db.read(|conn| {
            conn.execute("INSERT INTO ledger (note) VALUES ('sneaky')", [])?;
            Ok(())
        }));

        assert!(matches!(result, Err(DbError::Sqlite(_))));
        assert_eq!(notes(&db), Vec::<String>::new());
    }

    #[test]
    fn the_writer_is_durable_and_uses_the_write_ahead_log() {
        // The durable engine records a transaction before broadcasting it, so
        // a commit must survive power loss (synchronous = FULL = 2).
        let dir = tempfile::tempdir().unwrap();
        let db = block_on(Db::open(file_config(&dir))).unwrap();

        let settings: (String, i64, i64) = block_on(db.write(|tx| {
            Ok((
                tx.pragma_query_value(None, "journal_mode", |row| row.get(0))?,
                tx.pragma_query_value(None, "synchronous", |row| row.get(0))?,
                tx.pragma_query_value(None, "foreign_keys", |row| row.get(0))?,
            ))
        }))
        .unwrap();

        assert_eq!(settings, ("wal".to_owned(), 2, 1));
    }

    #[test]
    fn status_reports_the_file_schema_and_sqlite_version() {
        // Hosts read this to confirm on a device that the bundled SQLite
        // opened the configured file and applied every migration.
        let dir = tempfile::tempdir().unwrap();
        let db = block_on(Db::open(file_config(&dir))).unwrap();

        let status = block_on(db.status()).unwrap();

        let expected_path = dir.path().canonicalize().unwrap().join("core.sqlite3");
        assert_eq!(
            status,
            DbStatus {
                sqlite_version: rusqlite::version().to_owned(),
                schema_version: 2,
                path: Some(expected_path.to_string_lossy().into_owned()),
            }
        );
    }

    #[test]
    fn a_closed_database_rejects_further_work() {
        let db = block_on(Db::open(memory_config())).unwrap();
        block_on(db.close()).unwrap();

        assert!(matches!(insert(&db, "late"), Err(DbError::Closed)));
    }

    #[test]
    fn lazy_open_retries_after_a_failure() {
        // Hosts validate the directory up front, but a later open can still
        // fail; the error must reach the caller and must not stick forever.
        let dir = tempfile::tempdir().unwrap();
        let missing = dir.path().join("not-yet");
        let lazy = LazyDb::new(DbConfig {
            location: DbLocation::File(missing.join("core.sqlite3")),
            migrations,
            readers: 1,
        });

        assert!(matches!(block_on(lazy.get()), Err(DbError::Open(_))));

        std::fs::create_dir(&missing).unwrap();
        let db = block_on(lazy.get()).unwrap();
        insert(&db, "after retry").unwrap();

        let same = block_on(lazy.get()).unwrap();
        let seen: Option<String> = block_on(same.read(|conn| {
            Ok(conn
                .query_row("SELECT note FROM ledger", [], |row| row.get(0))
                .optional()?)
        }))
        .unwrap();
        assert_eq!(seen.as_deref(), Some("after retry"));
    }
}
