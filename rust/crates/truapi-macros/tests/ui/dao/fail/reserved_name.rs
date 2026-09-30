use truapi_macros::dao;

#[dao]
trait LedgerDao {
    #[query("SELECT count(*) FROM ledger")]
    fn new(&self) -> rusqlite::Result<i64>;
}

fn main() {}
