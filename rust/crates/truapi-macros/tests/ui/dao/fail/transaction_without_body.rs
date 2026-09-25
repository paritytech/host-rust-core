use truapi_macros::dao;

#[dao]
trait LedgerDao {
    #[transaction]
    fn transfer(&self, amount: i64) -> rusqlite::Result<()>;
}

fn main() {}
