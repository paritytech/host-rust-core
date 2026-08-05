use parity_scale_codec::{Decode, Encode};

use super::ProductAccountId;

/// A 32-byte value. Encodes exactly like `[u8; 32]` on the SCALE wire; passes
/// as plain bytes on FFI surfaces.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Encode, Decode)]
pub struct Bytes32(pub [u8; 32]);

#[cfg(feature = "uniffi")]
uniffi::custom_type!(Bytes32, Vec<u8>, {
    lower: |bytes| bytes.0.to_vec(),
    try_lift: |bytes| Ok(Bytes32(bytes.as_slice().try_into()?)),
});

impl From<[u8; 32]> for Bytes32 {
    fn from(bytes: [u8; 32]) -> Self {
        Self(bytes)
    }
}

impl From<Bytes32> for [u8; 32] {
    fn from(bytes: Bytes32) -> Self {
        bytes.0
    }
}

impl core::ops::Deref for Bytes32 {
    type Target = [u8; 32];

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl AsRef<[u8]> for Bytes32 {
    fn as_ref(&self) -> &[u8] {
        &self.0
    }
}

impl PartialEq<[u8; 32]> for Bytes32 {
    fn eq(&self, other: &[u8; 32]) -> bool {
        &self.0 == other
    }
}

impl PartialEq<Bytes32> for [u8; 32] {
    fn eq(&self, other: &Bytes32) -> bool {
        self == &other.0
    }
}

/// A 32-byte chain genesis hash used to identify the target chain.
pub type GenesisHash = Bytes32;

/// A 32-byte raw account identifier used for legacy (non-product) accounts.
pub type AccountId = Bytes32;

/// A signed extension for a transaction payload.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
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
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
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
///
/// Identical to [`ProductAccountTxPayload`] except the signer is a raw
/// 32-byte [`AccountId`].
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
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
