use truapi_macros::dao;

#[dao]
trait LedgerDao {
    #[inline]
    #[query("SELECT count(*) FROM ledger")]
    fn count(&self) -> rusqlite::Result<i64>;
}

fn main() {}
