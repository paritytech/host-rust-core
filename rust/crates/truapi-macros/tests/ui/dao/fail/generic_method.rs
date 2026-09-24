use truapi_macros::dao;

#[dao]
trait LedgerDao {
    #[query("SELECT count(*) FROM ledger WHERE amount = :amount")]
    fn count<T>(&self, amount: T) -> rusqlite::Result<i64>;
}

fn main() {}
