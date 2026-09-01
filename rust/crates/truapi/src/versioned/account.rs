//! Versioned wrappers for [`Account`](crate::api::Account) methods.

use crate::CallError;
use crate::v01;
use crate::versioned::Request as RequestEnvelope;
use crate::versioned::Subscription as SubscriptionEnvelope;

truapi_macros::versioned_type! {
    pub enum HostAccountGetRequest { V1 => v01::HostAccountGetRequest }
    pub enum HostAccountGetResponse { V1 => v01::HostAccountGetResponse }
    pub enum HostAccountGetError { V1 => v01::HostAccountGetError }
    pub enum HostAccountGetAliasRequest { V1 => v01::HostAccountGetAliasRequest }
    pub enum HostAccountGetAliasResponse { V1 => v01::ContextualAlias }
    pub enum HostAccountGetAliasError { V1 => v01::HostAccountGetAliasError }
    pub enum HostAccountCreateProofRequest { V1 => v01::HostAccountCreateProofRequest }
    pub enum HostAccountCreateProofResponse { V1 => v01::HostAccountCreateProofResponse }
    pub enum HostAccountCreateProofError { V1 => v01::HostAccountCreateProofError }
    pub enum HostAccountRegisterRingVrfKeyRequest { V1 => v01::HostAccountRegisterRingVrfKeyRequest }
    pub enum HostAccountRegisterRingVrfKeyResponse { V1 => v01::RingVrfPublicKey }
    pub enum HostAccountRegisterRingVrfKeyError { V1 => v01::HostAccountRegisterRingVrfKeyError }
    pub enum HostAccountListRingVrfKeysRequest { V1 => v01::HostAccountListRingVrfKeysRequest }
    pub enum HostAccountListRingVrfKeysResponse { V1 => Vec<v01::RegisteredRingVrfKey> }
    pub enum HostAccountListRingVrfKeysError { V1 => v01::HostAccountListRingVrfKeysError }
    pub enum HostAccountRingVrfSignRequest { V1 => v01::HostAccountRingVrfSignRequest }
    pub enum HostAccountRingVrfSignResponse { V1 => Vec<u8> }
    pub enum HostAccountRingVrfSignError { V1 => v01::HostAccountRingVrfSignError }
    pub enum HostAccountSignVrfRequest { V1 => v01::HostAccountSignVrfRequest }
    pub enum HostAccountSignVrfResponse { V1 => v01::VrfSignature }
    pub enum HostAccountSignVrfError { V1 => v01::HostAccountSignVrfError }
    pub enum HostGetLegacyAccountsRequest { V1 }
    pub enum HostGetLegacyAccountsResponse { V1 => v01::HostGetLegacyAccountsResponse }
    pub enum HostGetLegacyAccountsError { V1 => v01::HostAccountGetError }
    pub enum HostAccountConnectionStatusSubscribeItem { V1 => v01::HostAccountConnectionStatusSubscribeItem }
    pub enum HostRequestLoginRequest { V1 => v01::HostRequestLoginRequest }
    pub enum HostRequestLoginResponse { V1 => v01::HostRequestLoginResponse }
    pub enum HostRequestLoginError { V1 => v01::HostRequestLoginError }
    pub enum HostGetUserIdRequest { V1 }
    pub enum HostGetUserIdResponse { V1 => v01::HostGetUserIdResponse }
    pub enum HostGetUserIdError { V1 => v01::HostGetUserIdError }

    /// Wire-envelope version for
    /// [`Account::connection_status_subscribe`](crate::api::Account::connection_status_subscribe).
    /// Used only by the generated dispatcher/client.
    pub enum HostAccountConnectionStatusSubscribeVersion {
        V1 => SubscriptionEnvelope<(), v01::HostAccountConnectionStatusSubscribeItem, CallError<crate::latest::GenericError>>,
    }

    /// Wire-envelope version for [`Account::get_account`](crate::api::Account::get_account).
    /// Used only by the generated dispatcher/client.
    pub enum HostAccountGetVersion {
        V1 => RequestEnvelope<v01::HostAccountGetRequest, Result<v01::HostAccountGetResponse, CallError<v01::HostAccountGetError>>>,
    }

    /// Wire-envelope version for
    /// [`Account::get_account_alias`](crate::api::Account::get_account_alias).
    /// Used only by the generated dispatcher/client.
    pub enum HostAccountGetAliasVersion {
        V1 => RequestEnvelope<v01::HostAccountGetAliasRequest, Result<v01::ContextualAlias, CallError<v01::HostAccountGetAliasError>>>,
    }

    /// Wire-envelope version for
    /// [`Account::create_account_proof`](crate::api::Account::create_account_proof).
    /// Used only by the generated dispatcher/client.
    pub enum HostAccountCreateProofVersion {
        V1 => RequestEnvelope<v01::HostAccountCreateProofRequest, Result<v01::HostAccountCreateProofResponse, CallError<v01::HostAccountCreateProofError>>>,
    }

    /// Wire-envelope version for
    /// [`Account::get_legacy_accounts`](crate::api::Account::get_legacy_accounts).
    /// Used only by the generated dispatcher/client.
    pub enum HostGetLegacyAccountsVersion {
        V1 => RequestEnvelope<(), Result<v01::HostGetLegacyAccountsResponse, CallError<v01::HostAccountGetError>>>,
    }

    /// Wire-envelope version for [`Account::get_user_id`](crate::api::Account::get_user_id).
    /// Used only by the generated dispatcher/client.
    pub enum HostGetUserIdVersion {
        V1 => RequestEnvelope<(), Result<v01::HostGetUserIdResponse, CallError<v01::HostGetUserIdError>>>,
    }

    /// Wire-envelope version for [`Account::request_login`](crate::api::Account::request_login).
    /// Used only by the generated dispatcher/client.
    pub enum HostRequestLoginVersion {
        V1 => RequestEnvelope<v01::HostRequestLoginRequest, Result<v01::HostRequestLoginResponse, CallError<v01::HostRequestLoginError>>>,
    }

    /// Wire-envelope version for [`Account::sign_vrf`](crate::api::Account::sign_vrf).
    /// Used only by the generated dispatcher/client.
    pub enum HostAccountSignVrfVersion {
        V1 => RequestEnvelope<v01::HostAccountSignVrfRequest, Result<v01::VrfSignature, CallError<v01::HostAccountSignVrfError>>>,
    }

    /// Wire-envelope version for
    /// [`Account::register_ring_vrf_key`](crate::api::Account::register_ring_vrf_key).
    /// Used only by the generated dispatcher/client.
    pub enum HostAccountRegisterRingVrfKeyVersion {
        V1 => RequestEnvelope<v01::HostAccountRegisterRingVrfKeyRequest, Result<v01::RingVrfPublicKey, CallError<v01::HostAccountRegisterRingVrfKeyError>>>,
    }

    /// Wire-envelope version for
    /// [`Account::list_ring_vrf_keys`](crate::api::Account::list_ring_vrf_keys).
    /// Used only by the generated dispatcher/client.
    pub enum HostAccountListRingVrfKeysVersion {
        V1 => RequestEnvelope<v01::HostAccountListRingVrfKeysRequest, Result<Vec<v01::RegisteredRingVrfKey>, CallError<v01::HostAccountListRingVrfKeysError>>>,
    }

    /// Wire-envelope version for [`Account::ring_vrf_sign`](crate::api::Account::ring_vrf_sign).
    /// Used only by the generated dispatcher/client.
    pub enum HostAccountRingVrfSignVersion {
        V1 => RequestEnvelope<v01::HostAccountRingVrfSignRequest, Result<Vec<u8>, CallError<v01::HostAccountRingVrfSignError>>>,
    }
}
