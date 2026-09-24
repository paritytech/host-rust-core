//! Compiler contracts for the `#[dao]` attribute.

#[test]
fn dao_contracts() {
    let cases = trybuild::TestCases::new();
    cases.compile_fail("tests/ui/dao/fail/*.rs");
}
