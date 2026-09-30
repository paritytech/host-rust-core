use truapi_macros::dao;

#[dao]
trait LedgerDao {
    #[query("SELECT note FROM ledger WHERE amount >= ?1")]
    fn at_least(&self, min: i64) -> rusqlite::Result<Vec<String>>;
}

fn main() {}
