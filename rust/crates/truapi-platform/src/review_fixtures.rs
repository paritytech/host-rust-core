//! Canonical sample [`UserConfirmationReview`] values for host decoder fixtures.
//!
//! Host apps decode confirmation reviews from opaque SCALE bytes against
//! hand-written models, pinned by golden hex fixtures. These samples are the
//! canonical source of that hex: `cargo run -p truapi-platform --bin
//! review-fixtures` prints one `NAME=0x<hex>` line per sample. The golden test
//! in `tests/review_fixtures.rs` pins the same hex so any encoding or
//! variant-order change fails in this repo instead of silently breaking a
//! host's decoder.

use parity_scale_codec::Encode;
use truapi::latest::{
    AllocatableResource, DerivationIndex, HostSignPayloadData, ProductAccountId,
    ProductProofContext, RawPayload, RingLocation,
};
use truapi::v01::{
    HostAccountSignVrfRequest, HostSignPayloadRequest, HostSignPayloadWithLegacyAccountRequest,
    HostSignRawRequest, HostSignRawWithLegacyAccountRequest, LegacyAccountTxPayload,
    ProductAccountTxPayload, RingLocationJunction, VrfTranscriptItem,
};

use crate::{
    AccountAccessReview, AccountAliasReview, CreateProofReview, CreateTransactionReview,
    IdentityDisclosureReview, PreimageSubmitReview, ResourceAllocationReview, SignPayloadReview,
    SignRawReview, SignVrfReview, StatementStoreProductSignReview, UserConfirmationReview,
};

/// SCALE-encode a review as lowercase hex without a `0x` prefix.
pub fn encode_hex(review: &UserConfirmationReview) -> String {
    review.encode().iter().map(|b| format!("{b:02x}")).collect()
}

/// Sample product account shared by the signing fixtures.
fn product_account() -> ProductAccountId {
    ProductAccountId {
        dot_ns_identifier: "demo-product.dot".into(),
        derivation_index: DerivationIndex::Left(7),
    }
}

/// Sample extrinsic payload shared by the payload-signing fixtures.
fn payload_data() -> HostSignPayloadData {
    HostSignPayloadData {
        block_hash: vec![0xaa, 0xbb],
        block_number: vec![0x2a],
        era: vec![0x00],
        genesis_hash: vec![0x90, 0xb5],
        method: vec![0xde, 0xad, 0xbe, 0xef],
        nonce: vec![0x05],
        spec_version: vec![0x01],
        tip: vec![0x00],
        transaction_version: vec![0x02],
        signed_extensions: vec!["CheckNonce".into(), "CheckWeight".into()],
        version: 4,
        asset_id: Some(vec![0xfe]),
        metadata_hash: None,
        mode: Some(1),
        with_signed_transaction: Some(true),
    }
}

/// Sample ring location shared by the alias/proof fixtures.
fn ring_location() -> RingLocation {
    RingLocation {
        chain_id: [0x33; 32],
        junctions: vec![
            RingLocationJunction::PalletInstance(42),
            RingLocationJunction::CollectionId(vec![0x07]),
        ],
    }
}

/// One named sample per [`UserConfirmationReview`] variant, in variant-index
/// order (multi-shape variants contribute one sample per inner shape).
pub fn all() -> Vec<(&'static str, UserConfirmationReview)> {
    vec![
        (
            "SIGN_PAYLOAD_PRODUCT",
            UserConfirmationReview::SignPayload(SignPayloadReview::Product(
                HostSignPayloadRequest {
                    account: product_account(),
                    payload: payload_data(),
                },
            )),
        ),
        (
            "SIGN_PAYLOAD_LEGACY",
            UserConfirmationReview::SignPayload(SignPayloadReview::LegacyAccount(
                HostSignPayloadWithLegacyAccountRequest {
                    signer: "5LegacySignerAddr".into(),
                    payload: payload_data(),
                },
            )),
        ),
        (
            "SIGN_RAW_PRODUCT_BYTES",
            UserConfirmationReview::SignRaw(SignRawReview::Product(HostSignRawRequest {
                account: product_account(),
                payload: RawPayload::Bytes {
                    bytes: vec![0xca, 0xfe, 0xba, 0xbe],
                },
            })),
        ),
        (
            "SIGN_RAW_LEGACY_PAYLOAD",
            UserConfirmationReview::SignRaw(SignRawReview::LegacyAccount(
                HostSignRawWithLegacyAccountRequest {
                    signer: "5LegacySignerAddr".into(),
                    payload: RawPayload::Payload {
                        payload: "hello world".into(),
                    },
                },
            )),
        ),
        (
            "STATEMENT_STORE_PRODUCT_SIGN",
            UserConfirmationReview::StatementStoreProductSign(StatementStoreProductSignReview {
                account: product_account(),
                payload: vec![0x51, 0x52, 0x53],
            }),
        ),
        (
            "CREATE_TX_PRODUCT",
            UserConfirmationReview::CreateTransaction(CreateTransactionReview::Product(
                ProductAccountTxPayload {
                    signer: product_account(),
                    genesis_hash: [0x11; 32],
                    call_data: vec![0xde, 0xad, 0xbe, 0xef],
                    extensions: vec![],
                    tx_ext_version: 0,
                },
            )),
        ),
        (
            "CREATE_TX_LEGACY",
            UserConfirmationReview::CreateTransaction(CreateTransactionReview::LegacyAccount(
                LegacyAccountTxPayload {
                    signer: [0x22; 32],
                    genesis_hash: [0x11; 32],
                    call_data: vec![0xde, 0xad, 0xbe, 0xef],
                    extensions: vec![],
                    tx_ext_version: 0,
                },
            )),
        ),
        (
            "ACCOUNT_ALIAS",
            UserConfirmationReview::AccountAlias(AccountAliasReview {
                calling_product_id: "demo-product.dot".into(),
                context: ProductProofContext {
                    product_id: "demo-product.dot".into(),
                    suffix: DerivationIndex::Left(7),
                },
                ring_location: ring_location(),
            }),
        ),
        (
            "CREATE_PROOF",
            UserConfirmationReview::CreateProof(CreateProofReview {
                calling_product_id: "demo-product.dot".into(),
                context: ProductProofContext {
                    product_id: "demo-product.dot".into(),
                    suffix: DerivationIndex::Left(7),
                },
                ring_location: ring_location(),
                message: vec![0x4d, 0x4d],
            }),
        ),
        (
            "IDENTITY_DISCLOSURE",
            UserConfirmationReview::IdentityDisclosure(IdentityDisclosureReview {
                product_id: "demo-product.dot".into(),
            }),
        ),
        (
            "RESOURCE_ALLOCATION",
            UserConfirmationReview::ResourceAllocation(ResourceAllocationReview {
                calling_product_id: "demo-product.dot".into(),
                resources: vec![
                    AllocatableResource::StatementStoreAllowance,
                    AllocatableResource::AutoSigning,
                ],
            }),
        ),
        (
            "PREIMAGE_SUBMIT",
            UserConfirmationReview::PreimageSubmit(PreimageSubmitReview { size: 1024 }),
        ),
        (
            "ACCOUNT_ACCESS",
            UserConfirmationReview::AccountAccess(AccountAccessReview {
                requesting_product_id: "demo-product.dot".into(),
                target_product_id: "other-product.dot".into(),
            }),
        ),
        (
            "SIGN_VRF",
            UserConfirmationReview::SignVrf(SignVrfReview {
                calling_product_id: "demo-product.dot".into(),
                request: HostAccountSignVrfRequest {
                    account: product_account(),
                    transcript_label: b"demo-transcript".to_vec(),
                    items: vec![VrfTranscriptItem {
                        label: b"item".to_vec(),
                        value: vec![0x01, 0x02],
                    }],
                },
            }),
        ),
    ]
}
