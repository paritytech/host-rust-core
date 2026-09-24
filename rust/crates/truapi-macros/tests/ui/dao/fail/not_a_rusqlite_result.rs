use truapi_macros::dao;

#[dao]
trait LedgerDao {
    #[query("SELECT note FROM ledger")]
    fn all(&self) -> Vec<String>;
}

fn main() {}
