use futures::executor::block_on;
use rusqlite_migration::{M, Migrations};
use truapi_macros::dao;

use super::*;

fn migrations() -> Migrations<'static> {
    Migrations::new(vec![M::up(
        "CREATE TABLE ledger (
            id INTEGER PRIMARY KEY,
            note TEXT NOT NULL UNIQUE,
            amount INTEGER NOT NULL,
            payload BLOB NOT NULL,
            memo TEXT
        );
        CREATE TABLE other (id INTEGER PRIMARY KEY, value INTEGER NOT NULL);",
    )])
}

#[derive(Debug, PartialEq, serde::Deserialize)]
struct Entry {
    id: i64,
    note: String,
    amount: i64,
}

#[derive(Debug, PartialEq, serde::Deserialize)]
struct Payload {
    #[serde(with = "serde_bytes")]
    payload: Vec<u8>,
}

#[derive(Debug, serde::Deserialize)]
#[allow(dead_code, reason = "only deserialized, to provoke a decode error")]
struct MisTyped {
    id: i64,
    amount: String,
}

/// Balances kept per note.
#[dao]
trait LedgerDao {
    #[query("SELECT id, note, amount FROM ledger WHERE amount >= :min ORDER BY id")]
    fn at_least(&self, min: i64) -> rusqlite::Result<Vec<Entry>>;

    #[query("SELECT id, note, amount FROM ledger WHERE note = :note")]
    fn find(&self, note: &str) -> rusqlite::Result<Option<Entry>>;

    #[query("SELECT count(*) FROM ledger")]
    fn count(&self) -> rusqlite::Result<i64>;

    #[query("SELECT payload FROM ledger WHERE id = :id")]
    fn payload(&self, id: i64) -> rusqlite::Result<Payload>;

    #[query("SELECT id, amount FROM ledger WHERE id = :id")]
    fn mistyped(&self, id: i64) -> rusqlite::Result<MisTyped>;

    #[query("SELECT memo FROM ledger WHERE id = :id")]
    fn memo(&self, id: i64) -> rusqlite::Result<Option<Option<String>>>;

    #[execute(
        "INSERT INTO ledger (note, amount, payload) VALUES (:note, :amount, :payload) RETURNING id"
    )]
    fn insert(&self, note: &str, amount: i64, payload: &[u8]) -> rusqlite::Result<i64>;

    #[execute(
        "INSERT OR IGNORE INTO ledger (note, amount, payload) VALUES (:note, 0, x'') RETURNING id"
    )]
    fn ensure(&self, note: &str) -> rusqlite::Result<Option<i64>>;

    #[execute("INSERT INTO other (value) VALUES (:value)")]
    fn insert_other(&self, value: i64) -> rusqlite::Result<()>;

    #[execute("UPDATE ledger SET amount = :amount WHERE note = :note")]
    fn set_amount(&self, note: &str, amount: i64) -> rusqlite::Result<usize>;

    #[execute("UPDATE ledger SET memo = :memo WHERE id = :id")]
    fn set_memo(&self, id: i64, memo: Option<&str>) -> rusqlite::Result<usize>;

    #[query(
        "SELECT count(*) FROM ledger
         WHERE note IN (:statement, :connection, :params, :rows, :row, :type)"
    )]
    fn named_like_generated_locals(
        &self,
        statement: &str,
        connection: &str,
        params: &str,
        rows: &str,
        row: &str,
        r#type: &str,
    ) -> rusqlite::Result<i64>;

    #[allow(
        clippy::needless_lifetimes,
        reason = "checks that a named lifetime reaches the async twin"
    )]
    #[query("SELECT count(*) FROM ledger WHERE note = :note")]
    fn with_lifetime<'a>(&self, note: &'a str) -> rusqlite::Result<i64>;

    #[cfg(any())]
    #[query("SELECT column_that_does_not_exist FROM ledger")]
    fn compiled_out(&self) -> rusqlite::Result<i64>;

    #[allow(
        clippy::too_many_arguments,
        reason = "checks that `allow` reaches every generated item"
    )]
    #[query("SELECT count(*) FROM ledger WHERE amount IN (:a, :b, :c, :d, :e, :f, :g, :h)")]
    fn among(
        &self,
        a: i64,
        b: i64,
        c: i64,
        d: i64,
        e: i64,
        f: i64,
        g: i64,
        h: i64,
    ) -> rusqlite::Result<i64>;

    /// Moves `amount` between two notes, or changes nothing.
    #[transaction]
    fn transfer(&self, from: &str, to: &str, amount: i64) -> rusqlite::Result<()> {
        let source = self
            .find(from)?
            .ok_or(rusqlite::Error::QueryReturnedNoRows)?;
        self.set_amount(from, source.amount - amount)?;
        let target = self.find(to)?.ok_or(rusqlite::Error::QueryReturnedNoRows)?;
        self.set_amount(to, target.amount + amount)?;
        Ok(())
    }
}

/// A second DAO whose transaction composes the first one's.
#[dao]
trait AuditDao {
    #[execute("INSERT INTO other (value) VALUES (:value)")]
    fn record(&self, value: i64) -> rusqlite::Result<()>;

    #[query("SELECT count(*) FROM other")]
    fn recorded(&self) -> rusqlite::Result<i64>;

    /// Transfers and records the amount, or does neither.
    #[transaction]
    fn audited_transfer(&self, from: &str, to: &str, amount: i64) -> rusqlite::Result<()> {
        self.record(amount)?;
        self.transfer(from, to, amount)
    }
}

/// A query that writes: fine on the writer, refused on a reader.
#[dao]
trait WritingQueryDao {
    #[query("INSERT INTO other (value) VALUES (1) RETURNING id")]
    fn sneaky(&self) -> rusqlite::Result<i64>;
}

// `LedgerDaoTransactions` must not be implemented for a bare connection: its
// methods would then run without the transaction they rely on.
trait AmbiguousIfTransactional<Marker> {
    fn check() {}
}
impl<T: ?Sized> AmbiguousIfTransactional<()> for T {}
struct Transactional;
impl<T: ?Sized + LedgerDaoTransactions> AmbiguousIfTransactional<Transactional> for T {}
const _: fn() = || <rusqlite::Connection as AmbiguousIfTransactional<_>>::check();

/// A file database, so queries run on the read-only pool as in production.
/// Keep the directory alive for as long as the database is used.
fn open() -> (tempfile::TempDir, Db, LedgerDaoDb) {
    let dir = tempfile::tempdir().unwrap();
    let db = block_on(Db::open(DbConfig {
        location: DbLocation::File(dir.path().join("core.sqlite3")),
        migrations,
        readers: 1,
    }))
    .unwrap();
    (dir, db.clone(), LedgerDaoDb::new(db))
}

#[test]
fn async_methods_take_a_connection_from_the_database_themselves() {
    // The Room-style surface: callers hold only the DAO, never a connection.
    let (_dir, _, dao) = open();
    let alice = block_on(dao.insert("alice", 10, &[1, 2])).unwrap();
    let bob = block_on(dao.insert("bob", 3, &[])).unwrap();

    let rows = block_on(dao.at_least(0)).unwrap();

    assert_eq!(
        rows,
        vec![
            Entry {
                id: alice,
                note: "alice".into(),
                amount: 10
            },
            Entry {
                id: bob,
                note: "bob".into(),
                amount: 3
            },
        ]
    );
}

#[test]
fn row_shapes_follow_the_declared_return_type() {
    let (_dir, _, dao) = open();
    let id = block_on(dao.insert("alice", 10, &[7, 7])).unwrap();

    let shapes = (
        block_on(dao.find("alice"))
            .unwrap()
            .map(|entry| entry.amount),
        block_on(dao.find("nobody")).unwrap(),
        block_on(dao.count()).unwrap(),
        block_on(dao.payload(id)).unwrap(),
        block_on(dao.memo(id)).unwrap(),
    );

    assert_eq!(
        shapes,
        (
            Some(10),
            None,
            1,
            Payload {
                payload: vec![7, 7]
            },
            Some(None)
        )
    );
}

#[test]
fn a_query_for_exactly_one_row_fails_when_there_is_none() {
    let (_dir, _, dao) = open();

    let result = block_on(dao.payload(42));

    assert!(matches!(
        result,
        Err(DbError::Sqlite(rusqlite::Error::QueryReturnedNoRows))
    ));
}

#[test]
fn execute_reports_the_rows_it_changed() {
    let (_dir, _, dao) = open();
    block_on(dao.insert("alice", 10, &[])).unwrap();

    let changed = (
        block_on(dao.set_amount("alice", 11)).unwrap(),
        block_on(dao.set_amount("nobody", 11)).unwrap(),
    );

    assert_eq!(changed, (1, 0));
}

#[test]
fn an_insert_that_inserts_nothing_reports_no_id() {
    // An id read from `last_insert_rowid()` would name whatever row the shared
    // writer inserted last, here a row in a different table.
    let (_dir, _, dao) = open();
    let first = block_on(dao.ensure("k")).unwrap();
    for value in 0..5 {
        block_on(dao.insert_other(value)).unwrap();
    }

    let again = block_on(dao.ensure("k")).unwrap();

    assert_eq!((first, again), (Some(1), None));
}

#[test]
fn an_optional_borrowed_argument_binds_null_or_the_value() {
    let (_dir, _, dao) = open();
    let id = block_on(dao.insert("alice", 10, &[])).unwrap();

    block_on(dao.set_memo(id, Some("paid"))).unwrap();
    let set = block_on(dao.memo(id)).unwrap();
    block_on(dao.set_memo(id, None)).unwrap();
    let cleared = block_on(dao.memo(id)).unwrap();

    assert_eq!((set, cleared), (Some(Some("paid".to_owned())), Some(None)));
}

#[test]
fn arguments_may_share_names_with_generated_locals() {
    let (_dir, _, dao) = open();
    block_on(dao.insert("row", 1, &[])).unwrap();
    block_on(dao.insert("type", 1, &[])).unwrap();

    let found = block_on(dao.named_like_generated_locals(
        "statement",
        "connection",
        "params",
        "rows",
        "row",
        "type",
    ))
    .unwrap();

    assert_eq!(found, 2);
}

#[test]
fn methods_may_name_lifetimes() {
    let (_dir, _, dao) = open();
    block_on(dao.insert("alice", 1, &[])).unwrap();

    assert_eq!(block_on(dao.with_lifetime("alice")).unwrap(), 1);
}

#[test]
fn a_row_that_does_not_decode_names_the_real_column_and_type() {
    let (_dir, _, dao) = open();
    let id = block_on(dao.insert("alice", 10, &[])).unwrap();

    let error = block_on(dao.mistyped(id)).unwrap_err();

    assert!(
        matches!(
            error,
            DbError::Sqlite(rusqlite::Error::FromSqlConversionFailure(
                1,
                rusqlite::types::Type::Integer,
                _
            ))
        ),
        "{error:?}"
    );
}

#[test]
fn a_failing_transaction_method_changes_nothing() {
    // `transfer` debits before it looks up the target; without one enclosing
    // write the debit would survive the failed credit.
    let (_dir, _, dao) = open();
    block_on(dao.insert("alice", 10, &[])).unwrap();

    let result = block_on(dao.transfer("alice", "nobody", 4));

    assert!(result.is_err());
    assert_eq!(
        block_on(dao.find("alice"))
            .unwrap()
            .map(|entry| entry.amount),
        Some(10)
    );
}

#[test]
fn a_transaction_method_applies_every_change_together() {
    let (_dir, _, dao) = open();
    block_on(dao.insert("alice", 10, &[])).unwrap();
    block_on(dao.insert("bob", 0, &[])).unwrap();

    block_on(dao.transfer("alice", "bob", 4)).unwrap();

    let balances: Vec<i64> = block_on(dao.at_least(0))
        .unwrap()
        .iter()
        .map(|entry| entry.amount)
        .collect();
    assert_eq!(balances, vec![6, 4]);
}

#[test]
fn sync_methods_compose_into_one_caller_owned_write() {
    // Several DAO calls, or several DAOs, commit or roll back together when
    // the caller runs them inside one `Db::write`.
    let (_dir, db, dao) = open();

    let result = block_on(db.write(|tx| {
        tx.insert("alice", 10, &[])?;
        tx.transfer("alice", "alice", 1)?;
        tx.insert("alice", 20, &[])?;
        Ok(())
    }));

    assert!(matches!(result, Err(DbError::Sqlite(_))));
    assert_eq!(block_on(dao.count()).unwrap(), 0);
}

#[test]
fn every_dao_statement_prepares_against_the_migrated_schema() {
    assert_eq!(prepare_all(migrations, LedgerDaoDb::QUERIES), Ok(()));
}

#[test]
fn a_statement_that_does_not_match_the_schema_is_reported() {
    let broken = [DaoStatement {
        sql: "SELECT missing_column FROM ledger",
        read_only: true,
    }];

    let failure = prepare_all(migrations, &broken).unwrap_err();

    assert_eq!(failure.0, broken[0].sql);
}

#[test]
fn a_query_that_writes_is_reported() {
    // Queries run on read-only connections in production; an in-memory test
    // database reads through the writer and would never notice.
    let failure = prepare_all(migrations, WritingQueryDaoDb::QUERIES).unwrap_err();

    assert_eq!(failure.0, WritingQueryDaoDb::QUERIES[0].sql);
}

#[test]
fn a_transaction_method_composes_another_daos_transaction() {
    // `audited_transfer` records first and then calls `LedgerDao::transfer`;
    // when the transfer fails, the record must go too.
    let (_dir, db, dao) = open();
    let audit = AuditDaoDb::new(db);
    block_on(dao.insert("alice", 10, &[])).unwrap();
    block_on(dao.insert("bob", 0, &[])).unwrap();

    block_on(audit.audited_transfer("alice", "bob", 4)).unwrap();
    let failed = block_on(audit.audited_transfer("alice", "nobody", 1));

    assert!(failed.is_err());
    assert_eq!(block_on(audit.recorded()).unwrap(), 1);
}
