use truapi_macros::dao;

#[dao]
trait LedgerDao {
    #[query("SELECT count(*) FROM ledger")]
    fn count(&self) -> rusqlite::Result<i64> {
        Ok(0)
    }
}

fn main() {}
