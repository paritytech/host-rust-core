//! FFI declarations for the user-confirmation review tree.
//!
//! The canonical review types cross the FFI boundary directly: every type
//! reachable from [`truapi_platform::UserConfirmationReview`] is declared
//! `#[uniffi::remote(...)]`, so hosts receive the canonical structs and enums
//! rather than mirrored copies. Each declaration restates the canonical
//! definition field by field and the compiler rejects any drift. Fixed-size
//! 32-byte arrays widen to `Vec<u8>` on the FFI surface via [`Bytes32`].

use truapi::v01::{
    AccountId, AllocatableResource, DerivationIndex, GenesisHash, HostAccountSignVrfRequest,
    HostSignPayloadData, HostSignPayloadRequest, HostSignPayloadWithLegacyAccountRequest,
    HostSignRawRequest, HostSignRawWithLegacyAccountRequest, LegacyAccountTxPayload,
    ProductAccountId, ProductAccountTxPayload, ProductProofContext, RawPayload, RingLocation,
    RingLocationJunction, TxPayloadExtension, VrfTranscriptItem,
};
use truapi_platform::{
    AccountAccessReview, AccountAliasReview, CreateProofReview, CreateTransactionReview,
    IdentityDisclosureReview, PreimageSubmitReview, ResourceAllocationReview, SignPayloadReview,
    SignRawReview, SignVrfReview, StatementStoreProductSignReview, UserConfirmationReview,
};

/// A 32-byte array (genesis hash, account id, raw derivation index) widened to
/// `Vec<u8>` on the FFI surface.
pub type Bytes32 = [u8; 32];

uniffi::custom_type!(Bytes32, Vec<u8>, {
    remote,
    lower: |bytes| bytes.to_vec(),
    try_lift: |bytes| Ok(Bytes32::try_from(bytes.as_slice())?),
});

/// Account selector within a product subtree: `Either<u32, [u8; 32]>`.
#[uniffi::remote(Enum)]
pub enum DerivationIndex {
    /// Plain account index.
    Left(u32),
    /// Raw 32-byte derivation index.
    Right([u8; 32]),
}

/// Identifies a product-specific account by combining a dotNS domain name with a
/// derivation index.
#[uniffi::remote(Record)]
pub struct ProductAccountId {
    /// A dotNS domain name identifier (e.g., `"my-product.dot"`).
    pub dot_ns_identifier: String,
    /// Account selector within the product subtree.
    pub derivation_index: DerivationIndex,
}

/// Raw data to sign -- either binary bytes or a string message.
#[uniffi::remote(Enum)]
pub enum RawPayload {
    /// Raw binary data to sign.
    Bytes {
        /// Raw binary payload bytes.
        bytes: Vec<u8>,
    },
    /// String message to sign.
    Payload {
        /// String payload to sign.
        payload: String,
    },
}

/// Full Substrate extrinsic signing payload with all fields needed for
/// signature generation.
#[uniffi::remote(Record)]
pub struct HostSignPayloadData {
    /// Reference block hash.
    pub block_hash: Vec<u8>,
    /// Reference block number.
    pub block_number: Vec<u8>,
    /// Mortality era encoding.
    pub era: Vec<u8>,
    /// Chain genesis hash.
    pub genesis_hash: Vec<u8>,
    /// SCALE-encoded call data.
    pub method: Vec<u8>,
    /// Account nonce.
    pub nonce: Vec<u8>,
    /// Runtime spec version.
    pub spec_version: Vec<u8>,
    /// Transaction tip.
    pub tip: Vec<u8>,
    /// Transaction format version.
    pub transaction_version: Vec<u8>,
    /// Extension identifiers.
    pub signed_extensions: Vec<String>,
    /// Extrinsic version.
    pub version: u32,
    /// For multi-asset tips.
    pub asset_id: Option<Vec<u8>>,
    /// CheckMetadataHash extension.
    pub metadata_hash: Option<Vec<u8>>,
    /// Metadata mode.
    pub mode: Option<u32>,
    /// Request signed transaction back.
    pub with_signed_transaction: Option<bool>,
}

/// Request to sign an extrinsic payload with a product account.
#[uniffi::remote(Record)]
pub struct HostSignPayloadRequest {
    /// Product account that will sign this payload.
    pub account: ProductAccountId,
    /// The extrinsic payload to sign.
    pub payload: HostSignPayloadData,
}

/// Sign a Substrate extrinsic payload with a non-product (legacy) account.
#[uniffi::remote(Record)]
pub struct HostSignPayloadWithLegacyAccountRequest {
    /// Signer address (SS58 or hex) of the legacy account.
    pub signer: String,
    /// The extrinsic payload to sign.
    pub payload: HostSignPayloadData,
}

/// Review shown before a sign-payload request is sent to the paired wallet.
#[uniffi::remote(Enum)]
pub enum SignPayloadReview {
    /// Product-account signing request.
    Product(HostSignPayloadRequest),
    /// Legacy-account signing request.
    LegacyAccount(HostSignPayloadWithLegacyAccountRequest),
}

/// A raw signing request pairing an account with the payload to sign.
#[uniffi::remote(Record)]
pub struct HostSignRawRequest {
    /// Product account that will sign this payload.
    pub account: ProductAccountId,
    /// The payload to sign.
    pub payload: RawPayload,
}

/// Sign raw bytes with a non-product (legacy) account.
#[uniffi::remote(Record)]
pub struct HostSignRawWithLegacyAccountRequest {
    /// Signer address (SS58 or hex) of the legacy account.
    pub signer: String,
    /// The data to sign.
    pub payload: RawPayload,
}

/// Review shown before a sign-raw request is sent to the paired wallet.
#[uniffi::remote(Enum)]
pub enum SignRawReview {
    /// Product-account raw signing request.
    Product(HostSignRawRequest),
    /// Legacy-account raw signing request.
    LegacyAccount(HostSignRawWithLegacyAccountRequest),
}

/// Review shown before a product account signs a Statement Store proof
/// payload. The payload is the exact unsigned statement, signed as-is (no
/// `<Bytes>` envelope), so hosts must not present it with the raw-signing
/// convention.
#[uniffi::remote(Record)]
pub struct StatementStoreProductSignReview {
    /// Product account that will sign the statement payload.
    pub account: ProductAccountId,
    /// Exact unsigned statement payload to be signed.
    pub payload: Vec<u8>,
}

/// One transaction extension supplied by the caller.
#[uniffi::remote(Record)]
pub struct TxPayloadExtension {
    /// Extension name (e.g., `"CheckSpecVersion"`).
    pub id: String,
    /// SCALE-encoded extra data (in extrinsic body).
    pub extra: Vec<u8>,
    /// SCALE-encoded implicit data (signed, not in body).
    pub additional_signed: Vec<u8>,
}

/// Transaction payload for a product account.
#[uniffi::remote(Record)]
pub struct ProductAccountTxPayload {
    /// Product account that will sign the transaction.
    pub signer: ProductAccountId,
    /// Chain where the transaction will execute.
    pub genesis_hash: GenesisHash,
    /// SCALE-encoded Call data.
    pub call_data: Vec<u8>,
    /// Transaction extensions supplied by the caller.
    pub extensions: Vec<TxPayloadExtension>,
    /// 0 for Extrinsic V4, runtime-supported value for V5.
    pub tx_ext_version: u8,
}

/// Transaction payload for a legacy (non-product) account.
#[uniffi::remote(Record)]
pub struct LegacyAccountTxPayload {
    /// Raw 32-byte public key of the legacy account.
    pub signer: AccountId,
    /// Chain where the transaction will execute.
    pub genesis_hash: GenesisHash,
    /// SCALE-encoded Call data.
    pub call_data: Vec<u8>,
    /// Transaction extensions supplied by the caller.
    pub extensions: Vec<TxPayloadExtension>,
    /// 0 for Extrinsic V4, runtime-supported value for V5.
    pub tx_ext_version: u8,
}

/// Review shown before a transaction-creation request is sent to the paired wallet.
#[uniffi::remote(Enum)]
pub enum CreateTransactionReview {
    /// Product-account transaction request.
    Product(ProductAccountTxPayload),
    /// Legacy-account transaction request.
    LegacyAccount(LegacyAccountTxPayload),
}

/// A single step in a [`RingLocation`] path, addressing a ring within a chain.
#[uniffi::remote(Enum)]
pub enum RingLocationJunction {
    /// Pallet instance hosting the ring collection.
    PalletInstance(u8),
    /// Ring collection identifier within the pallet.
    CollectionId(Vec<u8>),
}

/// Locates a ring for ring VRF operations.
#[uniffi::remote(Record)]
pub struct RingLocation {
    /// Genesis hash of the chain hosting the ring.
    pub chain_id: GenesisHash,
    /// Path addressing the ring within the chain.
    pub junctions: Vec<RingLocationJunction>,
}

/// A product-scoped proof context: a product and a context within it.
#[uniffi::remote(Record)]
pub struct ProductProofContext {
    /// dotNS product identifier (e.g. `"my-product.dot"`) scoping the context.
    pub product_id: String,
    /// Selector distinguishing contexts within the product; expands to the
    /// same 32-byte derivation index as [`ProductAccountId::derivation_index`].
    pub suffix: DerivationIndex,
}

/// Review shown before a product derives a contextual alias (RFC 0004).
#[uniffi::remote(Record)]
pub struct AccountAliasReview {
    /// Product requesting the alias.
    pub calling_product_id: String,
    /// Product-scoped context the alias is bound to.
    pub context: ProductProofContext,
    /// Ring the alias is derived against.
    pub ring_location: RingLocation,
}

/// Review shown before a product creates a ring-VRF proof (RFC 0004).
#[uniffi::remote(Record)]
pub struct CreateProofReview {
    /// Product requesting the proof.
    pub calling_product_id: String,
    /// Product-scoped context the proof's alias is bound to.
    pub context: ProductProofContext,
    /// Ring the proof is generated against.
    pub ring_location: RingLocation,
    /// Opaque message bound into the proof.
    pub message: Vec<u8>,
}

/// One `append_message` call replayed against the signing transcript.
#[uniffi::remote(Record)]
pub struct VrfTranscriptItem {
    /// Merlin `append_message` label.
    pub label: Vec<u8>,
    /// Merlin `append_message` value.
    pub value: Vec<u8>,
}

/// Request to produce an sr25519 VRF signature from a product account over a
/// caller-supplied Merlin transcript.
#[uniffi::remote(Record)]
pub struct HostAccountSignVrfRequest {
    /// Account whose key signs the VRF.
    pub account: ProductAccountId,
    /// Root domain-separation label: `Transcript::new(transcript_label)`.
    pub transcript_label: Vec<u8>,
    /// Transcript items replayed in order as `append_message(label, value)`.
    pub items: Vec<VrfTranscriptItem>,
}

/// Review shown before signing an RFC-0023 VRF transcript.
#[uniffi::remote(Record)]
pub struct SignVrfReview {
    /// Product making the request.
    pub calling_product_id: String,
    /// Product account and exact ordered transcript.
    pub request: HostAccountSignVrfRequest,
}

/// A resource the host can pre-allocate on behalf of the product (RFC 0010).
#[uniffi::remote(Enum)]
pub enum AllocatableResource {
    /// Statement Store slot allowance for the product's own allowance account.
    StatementStoreAllowance,
    /// Bulletin chain slot allowance for the product's own allowance account.
    BulletinAllowance,
    /// Pre-warmed PGAS balance for the product account selected by this
    /// derivation index.
    SmartContractAllowance(DerivationIndex),
    /// Permission to sign on the product's behalf without per-call user prompts.
    AutoSigning,
}

/// Review shown before allocating resources for a product. Names the
/// beneficiary product so the user knows which product receives the
/// (signing-capable) allowance key they are approving.
#[uniffi::remote(Record)]
pub struct ResourceAllocationReview {
    /// Product the allocation is requested for.
    pub calling_product_id: String,
    /// Resources to allocate.
    pub resources: Vec<AllocatableResource>,
}

/// Review shown before a product asks to access another product account.
#[uniffi::remote(Record)]
pub struct AccountAccessReview {
    /// Product currently handling the request.
    pub requesting_product_id: String,
    /// Product whose account is being requested.
    pub target_product_id: String,
}

/// Review shown before a product learns the user's primary identity.
#[uniffi::remote(Record)]
pub struct IdentityDisclosureReview {
    /// Product currently handling the request.
    pub product_id: String,
}

/// Review shown before a preimage is submitted.
#[uniffi::remote(Record)]
pub struct PreimageSubmitReview {
    /// Size of the preimage in bytes.
    pub size: u64,
}

/// Review shown before a user-confirmed core action continues.
#[uniffi::remote(Enum)]
pub enum UserConfirmationReview {
    /// Sign a SCALE payload with a product or legacy account.
    SignPayload(SignPayloadReview),
    /// Sign raw bytes with a product or legacy account.
    SignRaw(SignRawReview),
    /// Sign a Statement Store proof payload with a product account.
    StatementStoreProductSign(StatementStoreProductSignReview),
    /// Create a transaction with a product or legacy account.
    CreateTransaction(CreateTransactionReview),
    /// Allow a product to derive a contextual alias for a ring.
    AccountAlias(AccountAliasReview),
    /// Allow a product to create a ring-VRF proof for a ring.
    CreateProof(CreateProofReview),
    /// Allow a product to learn the user's primary identity.
    IdentityDisclosure(IdentityDisclosureReview),
    /// Allocate resources for the requesting product.
    ResourceAllocation(ResourceAllocationReview),
    /// Submit a preimage to the host-selected backend.
    PreimageSubmit(PreimageSubmitReview),
    /// Allow a product to access another product account.
    AccountAccess(AccountAccessReview),
    /// Sign an RFC-0023 VRF transcript with a product account.
    SignVrf(SignVrfReview),
}

#[cfg(test)]
mod tests {
    use super::*;

    fn roundtrip(review: UserConfirmationReview) -> UserConfirmationReview {
        let mut buf = Vec::new();
        <UserConfirmationReview as uniffi::Lower<crate::UniFfiTag>>::write(review, &mut buf);
        <UserConfirmationReview as uniffi::Lift<crate::UniFfiTag>>::try_read(&mut buf.as_slice())
            .expect("review must lift back")
    }

    fn sign_payload_data() -> HostSignPayloadData {
        HostSignPayloadData {
            block_hash: vec![1; 32],
            block_number: vec![2],
            era: vec![3],
            genesis_hash: vec![4; 32],
            method: vec![5, 6],
            nonce: vec![7],
            spec_version: vec![8],
            tip: vec![9],
            transaction_version: vec![10],
            signed_extensions: vec!["CheckSpecVersion".to_string()],
            version: 4,
            asset_id: Some(vec![11]),
            metadata_hash: Some(vec![12; 32]),
            mode: Some(1),
            with_signed_transaction: Some(true),
        }
    }

    fn product_account() -> ProductAccountId {
        ProductAccountId {
            dot_ns_identifier: "app.dot".to_string(),
            derivation_index: DerivationIndex::Left(7),
        }
    }

    #[test]
    fn bytes32_widens_to_plain_bytes_on_the_wire() {
        let mut buf = Vec::new();
        <Bytes32 as uniffi::Lower<crate::UniFfiTag>>::write([7; 32], &mut buf);
        assert_eq!(buf[..4], 32i32.to_be_bytes());
        assert_eq!(buf[4..], [7; 32]);
    }

    #[test]
    fn every_review_variant_survives_the_ffi_roundtrip() {
        let cases = vec![
            UserConfirmationReview::SignPayload(SignPayloadReview::Product(
                HostSignPayloadRequest {
                    account: product_account(),
                    payload: sign_payload_data(),
                },
            )),
            UserConfirmationReview::SignPayload(SignPayloadReview::LegacyAccount(
                HostSignPayloadWithLegacyAccountRequest {
                    signer: "5F...".to_string(),
                    payload: sign_payload_data(),
                },
            )),
            UserConfirmationReview::SignRaw(SignRawReview::Product(HostSignRawRequest {
                account: product_account(),
                payload: RawPayload::Bytes { bytes: vec![1, 2] },
            })),
            UserConfirmationReview::SignRaw(SignRawReview::LegacyAccount(
                HostSignRawWithLegacyAccountRequest {
                    signer: "5F...".to_string(),
                    payload: RawPayload::Payload {
                        payload: "hello".to_string(),
                    },
                },
            )),
            UserConfirmationReview::StatementStoreProductSign(StatementStoreProductSignReview {
                account: product_account(),
                payload: vec![1, 2, 3],
            }),
            UserConfirmationReview::CreateTransaction(CreateTransactionReview::Product(
                ProductAccountTxPayload {
                    signer: product_account(),
                    genesis_hash: [14; 32],
                    call_data: vec![15],
                    extensions: vec![TxPayloadExtension {
                        id: "CheckNonce".to_string(),
                        extra: vec![16],
                        additional_signed: vec![],
                    }],
                    tx_ext_version: 0,
                },
            )),
            UserConfirmationReview::CreateTransaction(CreateTransactionReview::LegacyAccount(
                LegacyAccountTxPayload {
                    signer: [13; 32],
                    genesis_hash: [14; 32],
                    call_data: vec![15],
                    extensions: vec![],
                    tx_ext_version: 0,
                },
            )),
            UserConfirmationReview::AccountAlias(AccountAliasReview {
                calling_product_id: "app.dot".to_string(),
                context: ProductProofContext {
                    product_id: "app.dot".to_string(),
                    suffix: DerivationIndex::Left(1),
                },
                ring_location: RingLocation {
                    chain_id: [1; 32],
                    junctions: vec![
                        RingLocationJunction::PalletInstance(2),
                        RingLocationJunction::CollectionId(vec![3]),
                    ],
                },
            }),
            UserConfirmationReview::CreateProof(CreateProofReview {
                calling_product_id: "app.dot".to_string(),
                context: ProductProofContext {
                    product_id: "app.dot".to_string(),
                    suffix: DerivationIndex::Right([2; 32]),
                },
                ring_location: RingLocation {
                    chain_id: [1; 32],
                    junctions: vec![],
                },
                message: vec![9],
            }),
            UserConfirmationReview::IdentityDisclosure(IdentityDisclosureReview {
                product_id: "app.dot".to_string(),
            }),
            UserConfirmationReview::ResourceAllocation(ResourceAllocationReview {
                calling_product_id: "app.dot".to_string(),
                resources: vec![
                    AllocatableResource::StatementStoreAllowance,
                    AllocatableResource::BulletinAllowance,
                    AllocatableResource::SmartContractAllowance(DerivationIndex::Left(4)),
                    AllocatableResource::AutoSigning,
                ],
            }),
            UserConfirmationReview::PreimageSubmit(PreimageSubmitReview { size: 42 }),
            UserConfirmationReview::AccountAccess(AccountAccessReview {
                requesting_product_id: "a.dot".to_string(),
                target_product_id: "b.dot".to_string(),
            }),
            UserConfirmationReview::SignVrf(SignVrfReview {
                calling_product_id: "app.dot".to_string(),
                request: HostAccountSignVrfRequest {
                    account: product_account(),
                    transcript_label: b"vrf-label".to_vec(),
                    items: vec![VrfTranscriptItem {
                        label: b"item".to_vec(),
                        value: vec![1, 2, 3],
                    }],
                },
            }),
        ];

        for review in cases {
            assert_eq!(roundtrip(review.clone()), review);
        }
    }
}
