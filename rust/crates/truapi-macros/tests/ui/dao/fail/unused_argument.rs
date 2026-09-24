use truapi_macros::dao;

#[dao]
trait LedgerDao {
    #[query("SELECT note FROM ledger")]
    fn all(&self, min: i64) -> rusqlite::Result<Vec<String>>;
}

fn main() {}
