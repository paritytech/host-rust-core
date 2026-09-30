use truapi_macros::dao;

#[dao]
trait LedgerDao {
    #[query("SELECT note FROM ledger WHERE amount = :amount OR amount = #amount")]
    fn find(&self, amount: i64) -> rusqlite::Result<Vec<String>>;
}

fn main() {}
