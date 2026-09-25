use truapi_macros::dao;

#[dao]
trait LedgerDao {
    #[query("SELECT payload FROM ledger WHERE id = :id")]
    fn payload(&self, id: i64) -> rusqlite::Result<std::vec::Vec<core::primitive::u8>>;
}

fn main() {}
