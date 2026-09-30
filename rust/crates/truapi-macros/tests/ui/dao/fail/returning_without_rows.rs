use truapi_macros::dao;

#[dao]
trait LedgerDao {
    #[execute("INSERT INTO ledger (note) VALUES (:note) RETURNING id")]
    fn insert(&self, note: &str) -> rusqlite::Result<usize>;
}

fn main() {}
