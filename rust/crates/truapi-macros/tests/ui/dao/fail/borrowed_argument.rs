use truapi_macros::dao;

#[dao]
trait LedgerDao {
    #[execute("UPDATE ledger SET note = :note")]
    fn rename(&self, note: std::borrow::Cow<'_, str>) -> rusqlite::Result<usize>;
}

fn main() {}
