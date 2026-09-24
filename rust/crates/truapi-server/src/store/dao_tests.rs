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
            payload BLOB NOT NULL
        )",
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

    #[execute("INSERT INTO ledger (note, amount, payload) VALUES (:note, :amount, :payload)")]
    fn insert(&self, note: &str, amount: i64, payload: &[u8]) -> rusqlite::Result<i64>;

    #[execute("UPDATE ledger SET amount = :amount WHERE note = :note")]
    fn set_amount(&self, note: &str, amount: i64) -> rusqlite::Result<usize>;

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

fn open() -> LedgerDaoDb {
    let db = block_on(Db::open(DbConfig {
        location: DbLocation::Memory,
        migrations,
        readers: 1,
    }))
    .unwrap();
    LedgerDaoDb::new(db)
}

#[test]
fn async_methods_take_a_connection_from_the_database_themselves() {
    // The Room-style surface: callers hold only the DAO, never a connection.
    let dao = open();
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
    let dao = open();
    let id = block_on(dao.insert("alice", 10, &[7, 7])).unwrap();

    let shapes = (
        block_on(dao.find("alice"))
            .unwrap()
            .map(|entry| entry.amount),
        block_on(dao.find("nobody")).unwrap(),
        block_on(dao.count()).unwrap(),
        block_on(dao.payload(id)).unwrap(),
    );

    assert_eq!(
        shapes,
        (
            Some(10),
            None,
            1,
            Payload {
                payload: vec![7, 7]
            }
        )
    );
}

#[test]
fn a_query_for_exactly_one_row_fails_when_there_is_none() {
    let dao = open();

    let result = block_on(dao.payload(42));

    assert!(matches!(
        result,
        Err(DbError::Sqlite(rusqlite::Error::QueryReturnedNoRows))
    ));
}

#[test]
fn execute_reports_the_rows_it_changed() {
    let dao = open();
    block_on(dao.insert("alice", 10, &[])).unwrap();

    let changed = (
        block_on(dao.set_amount("alice", 11)).unwrap(),
        block_on(dao.set_amount("nobody", 11)).unwrap(),
    );

    assert_eq!(changed, (1, 0));
}

#[test]
fn a_failing_transaction_method_changes_nothing() {
    // `transfer` debits before it looks up the target; without one enclosing
    // write the debit would survive the failed credit.
    let dao = open();
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
    let dao = open();
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
    let db = block_on(Db::open(DbConfig {
        location: DbLocation::Memory,
        migrations,
        readers: 1,
    }))
    .unwrap();

    let result = block_on(db.write(|tx| {
        tx.insert("alice", 10, &[])?;
        tx.insert("alice", 20, &[])?;
        Ok(())
    }));

    assert!(matches!(result, Err(DbError::Sqlite(_))));
    assert_eq!(block_on(LedgerDaoDb::new(db).count()).unwrap(), 0);
}

#[test]
fn every_dao_query_prepares_against_the_migrated_schema() {
    assert_eq!(prepare_all(migrations, LedgerDaoDb::QUERIES), Ok(()));
}

#[test]
fn a_query_that_does_not_match_the_schema_is_reported() {
    let broken = ["SELECT missing_column FROM ledger"];

    let failure = prepare_all(migrations, &broken).unwrap_err();

    assert_eq!(failure.0, broken[0]);
}
