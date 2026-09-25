use truapi_macros::dao;

#[dao]
trait LedgerDao {
    #[execute("INSERT INTO ledger (note) VALUES (:note)")]
    fn insert(&self, note: &str) -> rusqlite::Result<i64>;
}

fn main() {}
