use truapi_macros::dao;

#[dao]
trait LedgerDao {
    #[query("SELECT count(*) FROM ledger WHERE amount = :amount")]
    fn count(&self, amount: &dyn rusqlite::ToSql) -> rusqlite::Result<i64>;
}

fn main() {}
