use truapi_macros::dao;

#[dao]
trait LedgerDao {
    #[query("SELECT count(*) FROM ledger")]
    fn clone(&self) -> rusqlite::Result<i64>;
}

fn main() {}
