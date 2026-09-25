use truapi_macros::dao;

#[dao]
trait LedgerDao {
    fn count(&self) -> rusqlite::Result<i64>;
}

fn main() {}
