use truapi_macros::dao;

#[dao]
trait LedgerDao {
    #[execute("DELETE FROM ledger")]
    fn execute(&self) -> rusqlite::Result<usize>;
}

fn main() {}
