use truapi_macros::dao;

#[dao]
trait LedgerDao {
    #[query("SELECT id, amount FROM ledger")]
    fn pairs(&self) -> rusqlite::Result<Vec<(i64, i64)>>;
}

fn main() {}
