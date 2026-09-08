//! V1 application messages exchanged on the encrypted SSO channel.
//!
//! Baseline variants are specified in host-spec B.5:
//! <https://github.com/paritytech/host-spec/blob/adb3989208ae1c2107dbf0159611353e6989422c/spec/B-inter-host.md?plain=1#L189-L208>
//! Additional deployed variants are tracked as divergence D-B.5.6:
//! <https://github.com/paritytech/host-spec/blob/adb3989208ae1c2107dbf0159611353e6989422c/divergences.md?plain=1#L26-L35>

use parity_scale_codec::{Decode, Encode};
use truapi_macros::SsoWire;

use super::{
    CreateAccountProofRequest, CreateAccountProofResponse, CreateTransactionRequest,
    CreateTransactionResponse, CreateTransactionWithLegacyAccountRequest, GetAccountAliasRequest,
    GetAccountAliasResponse, ListRingVrfKeysRequest, ListRingVrfKeysResponse,
    ProductSubtreeRequest, ProductSubtreeResponse, RegisterRingVrfKeyRequest,
    RegisterRingVrfKeyResponse, ResourceAllocationRequest, ResourceAllocationResponse,
    RingVrfSignRequest, RingVrfSignResponse, SignRawWithLegacyAccountRequest,
    SignRawWithLegacyAccountResponse, SignRequest, SignResponse, SignVrfRequest, SignVrfResponse,
};

/// v1 messages exchanged with the paired signing host over the encrypted SSO channel.
///
/// The variant order is part of the SCALE wire protocol used inside
/// statement-store session statements.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode, SsoWire)]
pub enum RemoteMessage {
    /// The peer is ending the SSO session.
    Disconnected,
    /// Ask the signing host to sign a payload or raw data with a product account.
    SignRequest(Box<SignRequest>),
    /// Signing host's answer to [`RemoteMessage::SignRequest`].
    SignResponse(SignResponse),
    /// Ask the Account Holder for a contextual alias.
    GetAccountAliasRequest(GetAccountAliasRequest),
    /// Account Holder's answer to [`RemoteMessage::GetAccountAliasRequest`].
    GetAccountAliasResponse(GetAccountAliasResponse),
    /// Ask the signing host to allocate SSO-backed resources.
    ResourceAllocationRequest(ResourceAllocationRequest),
    /// Signing host's answer to [`RemoteMessage::ResourceAllocationRequest`].
    ResourceAllocationResponse(ResourceAllocationResponse),
    /// Ask the signing host to create a signed product-account transaction.
    CreateTransactionRequest(CreateTransactionRequest),
    /// Signing host's answer to either transaction-creation request.
    CreateTransactionResponse(CreateTransactionResponse),
    /// Ask the signing host to create a signed legacy-account transaction.
    CreateTransactionWithLegacyAccountRequest(CreateTransactionWithLegacyAccountRequest),
    /// Ask the signing host to sign raw data with a legacy account.
    SignRawWithLegacyAccountRequest(SignRawWithLegacyAccountRequest),
    /// Signing host's answer to [`RemoteMessage::SignRawWithLegacyAccountRequest`].
    SignRawWithLegacyAccountResponse(SignRawWithLegacyAccountResponse),
    /// Ask the Account Holder for a ring-VRF proof.
    CreateAccountProofRequest(CreateAccountProofRequest),
    /// Account Holder's answer to [`RemoteMessage::CreateAccountProofRequest`].
    CreateAccountProofResponse(CreateAccountProofResponse),
    /// Ask the Account Holder to sign an RFC-0023 sr25519 VRF transcript.
    #[codec(index = 14)]
    SignVrfRequest(SignVrfRequest),
    /// Account Holder's answer to [`RemoteMessage::SignVrfRequest`].
    #[codec(index = 15)]
    SignVrfResponse(SignVrfResponse),
    /// Consent-free request for a product's hard-subtree public key.
    #[codec(index = 16)]
    ProductSubtreeRequest(ProductSubtreeRequest),
    /// Account Holder's answer to [`RemoteMessage::ProductSubtreeRequest`].
    #[codec(index = 17)]
    ProductSubtreeResponse(ProductSubtreeResponse),
    /// Register a ring-VRF key with the Account Holder.
    #[codec(index = 18)]
    RegisterRingVrfKeyRequest(RegisterRingVrfKeyRequest),
    /// Account Holder's answer to [`RemoteMessage::RegisterRingVrfKeyRequest`].
    #[codec(index = 19)]
    RegisterRingVrfKeyResponse(RegisterRingVrfKeyResponse),
    /// List registered ring-VRF keys.
    #[codec(index = 20)]
    ListRingVrfKeysRequest(ListRingVrfKeysRequest),
    /// Account Holder's answer to [`RemoteMessage::ListRingVrfKeysRequest`].
    #[codec(index = 21)]
    ListRingVrfKeysResponse(ListRingVrfKeysResponse),
    /// Sign bytes with a registered ring-VRF key.
    #[codec(index = 22)]
    RingVrfSignRequest(RingVrfSignRequest),
    /// Account Holder's answer to [`RemoteMessage::RingVrfSignRequest`].
    #[codec(index = 23)]
    RingVrfSignResponse(RingVrfSignResponse),
}
