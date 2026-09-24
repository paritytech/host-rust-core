use truapi_macros::dao;

#[dao]
trait LedgerDao {
    #[execute("UPDATE ledger SET memo = :memo")]
    fn set_memo(&self, memo: &Option<&str>) -> rusqlite::Result<usize>;
}

fn main() {}
