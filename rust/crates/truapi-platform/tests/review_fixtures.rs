//! Golden-fixture pin for `review_fixtures`: any change to the
//! [`UserConfirmationReview`] encoding (variant order, field order, field
//! types) turns this red here, instead of silently breaking a host app's
//! decoder.

use truapi_platform::UserConfirmationReview;
use truapi_platform::review_fixtures::{all, encode_hex};

/// (name, canonical SCALE hex) — regenerate with
/// `cargo run -p truapi-platform --bin review-fixtures` after an intentional
/// protocol change, and notify host apps to regenerate their fixtures.
const EXPECTED: &[(&str, &str)] = &[
    (
        "SIGN_PAYLOAD_PRODUCT",
        "00004064656d6f2d70726f647563742e646f74000700000008aabb042a04000890b510deadbeef04050401040004020828436865636b4e6f6e63652c436865636b576569676874040000000104fe0001010000000101",
    ),
    (
        "SIGN_PAYLOAD_LEGACY",
        "000144354c65676163795369676e65724164647208aabb042a04000890b510deadbeef04050401040004020828436865636b4e6f6e63652c436865636b576569676874040000000104fe0001010000000101",
    ),
    (
        "SIGN_RAW_PRODUCT_BYTES",
        "01004064656d6f2d70726f647563742e646f7400070000000010cafebabe",
    ),
    (
        "SIGN_RAW_LEGACY_PAYLOAD",
        "010144354c65676163795369676e657241646472012c68656c6c6f20776f726c64",
    ),
    (
        "STATEMENT_STORE_PRODUCT_SIGN",
        "024064656d6f2d70726f647563742e646f7400070000000c515253",
    ),
    (
        "CREATE_TX_PRODUCT",
        "03004064656d6f2d70726f647563742e646f740007000000111111111111111111111111111111111111111111111111111111111111111110deadbeef0000",
    ),
    (
        "CREATE_TX_LEGACY",
        "03012222222222222222222222222222222222222222222222222222222222222222111111111111111111111111111111111111111111111111111111111111111110deadbeef0000",
    ),
    (
        "ACCOUNT_ALIAS",
        "044064656d6f2d70726f647563742e646f744064656d6f2d70726f647563742e646f740007000000333333333333333333333333333333333333333333333333333333333333333308002a010407",
    ),
    (
        "CREATE_PROOF",
        "054064656d6f2d70726f647563742e646f744064656d6f2d70726f647563742e646f740007000000333333333333333333333333333333333333333333333333333333333333333308002a010407084d4d",
    ),
    (
        "IDENTITY_DISCLOSURE",
        "064064656d6f2d70726f647563742e646f74",
    ),
    (
        "RESOURCE_ALLOCATION",
        "074064656d6f2d70726f647563742e646f74080003",
    ),
    ("PREIMAGE_SUBMIT", "080004000000000000"),
    (
        "ACCOUNT_ACCESS",
        "094064656d6f2d70726f647563742e646f74446f746865722d70726f647563742e646f74",
    ),
    (
        "SIGN_VRF",
        "0a4064656d6f2d70726f647563742e646f744064656d6f2d70726f647563742e646f7400070000003c64656d6f2d7472616e73637269707404106974656d080102",
    ),
];

#[test]
fn encodings_are_stable() {
    let samples = all();
    assert_eq!(samples.len(), EXPECTED.len(), "sample count drifted");
    for ((name, review), (expected_name, expected_hex)) in samples.iter().zip(EXPECTED) {
        assert_eq!(name, expected_name, "sample order drifted");
        assert_eq!(
            &encode_hex(review),
            expected_hex,
            "{name}: encoding changed — regenerate host fixtures"
        );
    }
}

/// Compile-time tripwire: adding a [`UserConfirmationReview`] variant without
/// a sample fails the `match` below, forcing `review_fixtures::all()` (and
/// host fixtures) to be extended in the same change.
#[test]
fn every_variant_has_a_sample() {
    let mut seen = std::collections::BTreeSet::new();
    for (_, review) in all() {
        seen.insert(match review {
            UserConfirmationReview::SignPayload(_) => "SignPayload",
            UserConfirmationReview::SignRaw(_) => "SignRaw",
            UserConfirmationReview::StatementStoreProductSign(_) => "StatementStoreProductSign",
            UserConfirmationReview::CreateTransaction(_) => "CreateTransaction",
            UserConfirmationReview::AccountAlias(_) => "AccountAlias",
            UserConfirmationReview::CreateProof(_) => "CreateProof",
            UserConfirmationReview::IdentityDisclosure(_) => "IdentityDisclosure",
            UserConfirmationReview::ResourceAllocation(_) => "ResourceAllocation",
            UserConfirmationReview::PreimageSubmit(_) => "PreimageSubmit",
            UserConfirmationReview::AccountAccess(_) => "AccountAccess",
            UserConfirmationReview::SignVrf(_) => "SignVrf",
        });
    }
    assert_eq!(seen.len(), 11, "one sample missing for a review variant");
}
