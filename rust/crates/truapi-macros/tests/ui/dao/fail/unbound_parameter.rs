use truapi_macros::dao;

#[dao]
trait LedgerDao {
    #[query("SELECT note FROM ledger WHERE amount >= :min")]
    fn at_least(&self) -> rusqlite::Result<Vec<String>>;
}

fn main() {}
