use parity_scale_codec::{Decode, Encode};

use super::ProductAccountId;

/// A signed extension for a transaction payload.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(
    all(feature = "runtime", not(target_arch = "wasm32")),
    derive(uniffi::Record)
)]
pub struct TxPayloadExtension {
    /// Extension name (e.g., `"CheckSpecVersion"`).
    pub id: String,
    /// SCALE-encoded extra data (in extrinsic body).
    pub extra: Vec<u8>,
    /// SCALE-encoded implicit data (signed, not in body).
    pub additional_signed: Vec<u8>,
}

/// Transaction payload for a product account.
///
/// Contains everything the host needs to construct a signed extrinsic.
/// The signer is a [`ProductAccountId`]; the host resolves the
/// corresponding key pair through its account management layer.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(
    all(feature = "runtime", not(target_arch = "wasm32")),
    derive(uniffi::Record)
)]
pub struct ProductAccountTxPayload {
    /// Product account that will sign the transaction.
    pub signer: ProductAccountId,
    /// Chain where the transaction will execute.
    pub genesis_hash: [u8; 32],
    /// SCALE-encoded Call data.
    pub call_data: Vec<u8>,
    /// Transaction extensions supplied by the caller.
    pub extensions: Vec<TxPayloadExtension>,
    /// 0 for Extrinsic V4, runtime-supported value for V5.
    pub tx_ext_version: u8,
}

/// Transaction payload for a legacy (non-product) account.
///
/// Identical to [`ProductAccountTxPayload`] except the signer is a raw
/// 32-byte account identifier.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(
    all(feature = "runtime", not(target_arch = "wasm32")),
    derive(uniffi::Record)
)]
pub struct LegacyAccountTxPayload {
    /// Raw 32-byte public key of the legacy account.
    pub signer: [u8; 32],
    /// Chain where the transaction will execute.
    pub genesis_hash: [u8; 32],
    /// SCALE-encoded Call data.
    pub call_data: Vec<u8>,
    /// Transaction extensions supplied by the caller.
    pub extensions: Vec<TxPayloadExtension>,
    /// 0 for Extrinsic V4, runtime-supported value for V5.
    pub tx_ext_version: u8,
}

/// Transaction creation error.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub enum HostCreateTransactionError {
    /// Payload could not be deserialized.
    FailedToDecode,
    /// User rejected.
    Rejected,
    /// Unsupported payload version or extension.
    NotSupported {
        /// Unsupported payload or extension reason.
        reason: String,
    },
    /// Not authenticated.
    PermissionDenied,
    /// Catch-all.
    Unknown {
        /// Human-readable failure reason.
        reason: String,
    },
}
