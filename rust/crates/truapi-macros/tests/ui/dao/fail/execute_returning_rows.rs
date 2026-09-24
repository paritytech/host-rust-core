use truapi_macros::dao;

#[dao]
trait LedgerDao {
    #[execute("DELETE FROM ledger")]
    fn clear(&self) -> rusqlite::Result<Vec<String>>;
}

fn main() {}
