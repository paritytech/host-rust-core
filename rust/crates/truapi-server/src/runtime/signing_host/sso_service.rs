//! The signing host's answers to paired hosts: consent prompts, then the
//! local authority.

use std::sync::Arc;

use tracing::warn;
use truapi::latest as api;
use truapi::v01;
use truapi_platform::{
    CreateTransactionReview, ResourceAllocationReview, SignPayloadReview, SignRawReview,
    UserConfirmationReview,
};

use super::SigningHost;
use super::sso_responder::{
    AllowanceAllocationError, allocate_bulletin_allowance, allocate_smart_contract_allowance,
    allocate_statement_store_allowance,
};
use crate::host_logic::product_account::{
    derive_ring_vrf_domain_entropy, product_public_key_to_address,
};
use crate::host_logic::sso::messages::{
    CreateAccountProofRequest, CreateAccountProofResponse, CreateTransactionLegacyPayload,
    CreateTransactionPayload, CreateTransactionRequest, CreateTransactionResponse,
    CreateTransactionWithLegacyAccountRequest, GetAccountAliasRequest, GetAccountAliasResponse,
    ListRingVrfKeysRequest, ListRingVrfKeysResponse, OnExistingAllowancePolicy,
    ProductSubtreeRequest, ProductSubtreeResponse, RegisterRingVrfKeyRequest,
    RegisterRingVrfKeyResponse, ResourceAllocationRequest, ResourceAllocationResponse,
    RingVrfSignRequest, RingVrfSignResponse, SignRawWithLegacyAccountRequest,
    SignRawWithLegacyAccountResponse, SignRequest, SignResponse, SignVrfRequest, SignVrfResponse,
    SigningPayloadResponseData, SsoAllocatableResource, SsoAllocatedResource, SsoAllocationOutcome,
};
use crate::runtime::authority::{
    AuthorityError, AuthoritySession, CreateTransactionAuthorityRequest, ProductAuthority,
    SignPayloadAuthorityRequest, SignRawAuthorityRequest,
};
use crate::runtime::services::RuntimeServices;
use crate::runtime::sso_service::{SsoReply, SsoRequestContext};

/// SSO handlers served by a locally activated [`SigningHost`].
pub(crate) struct SigningHostSsoService {
    services: Arc<RuntimeServices>,
    signing_host: Arc<SigningHost>,
}

impl SigningHostSsoService {
    /// Serve requests with `signing_host`, prompting through `services`.
    pub(crate) fn new(services: Arc<RuntimeServices>, signing_host: Arc<SigningHost>) -> Self {
        Self {
            services,
            signing_host,
        }
    }

    /// The signing session captured before dispatching one request.
    pub(crate) fn current_session(&self) -> Option<AuthoritySession> {
        self.signing_host.current_session()
    }

    /// Run the platform confirmation seam; rejection and failure both refuse
    /// the operation with an opaque reason (host-spec B.7).
    async fn confirm(&self, review: UserConfirmationReview) -> Result<(), String> {
        match self.services.platform.confirm_user_action(review).await {
            Ok(true) => Ok(()),
            Ok(false) => Err("Rejected".to_string()),
            Err(err) => Err(format!("confirmation failed: {}", err.reason)),
        }
    }

    async fn serve_sign(
        &self,
        cx: &SsoRequestContext,
        request: SignRequest,
    ) -> Result<SigningPayloadResponseData, String> {
        let response = match request {
            SignRequest::Payload(request) => {
                let request: api::HostSignPayloadRequest = (*request).into();
                self.confirm(UserConfirmationReview::SignPayload(
                    SignPayloadReview::Product(request.clone()),
                ))
                .await?;
                self.signing_host
                    .sign_payload(
                        &cx.call,
                        &cx.session,
                        SignPayloadAuthorityRequest::Product(request),
                    )
                    .await
            }
            SignRequest::Raw(request) => {
                let request: api::HostSignRawRequest = request.into();
                self.confirm(UserConfirmationReview::SignRaw(SignRawReview::Product(
                    request.clone(),
                )))
                .await?;
                self.signing_host
                    .sign_raw(
                        &cx.call,
                        &cx.session,
                        SignRawAuthorityRequest::Product(request),
                    )
                    .await
            }
        }
        .map_err(|err| err.to_string())?;
        Ok(SigningPayloadResponseData {
            signature: response.signature,
            signed_transaction: response.signed_transaction,
        })
    }

    async fn serve_create_transaction(
        &self,
        cx: &SsoRequestContext,
        review: CreateTransactionReview,
        request: CreateTransactionAuthorityRequest,
    ) -> Result<Vec<u8>, String> {
        self.confirm(UserConfirmationReview::CreateTransaction(review))
            .await?;
        self.signing_host
            .create_transaction(&cx.call, &cx.session, request)
            .await
            .map(|response| response.transaction)
            .map_err(|err| err.to_string())
    }

    async fn allocate(
        &self,
        session: &AuthoritySession,
        calling_product_id: &str,
        resource: SsoAllocatableResource,
        on_existing: OnExistingAllowancePolicy,
    ) -> Result<SsoAllocationOutcome, AllowanceAllocationError> {
        let services = &self.services;
        let signing_host = &self.signing_host;
        match resource {
            SsoAllocatableResource::StatementStoreAllowance => allocate_statement_store_allowance(
                services,
                signing_host,
                session,
                calling_product_id,
                on_existing,
            )
            .await
            .map(|slot_account_key| {
                SsoAllocationOutcome::Allocated(SsoAllocatedResource::StatementStoreAllowance {
                    slot_account_key,
                })
            }),
            SsoAllocatableResource::BulletinAllowance => allocate_bulletin_allowance(
                services,
                signing_host,
                session,
                calling_product_id,
                on_existing,
            )
            .await
            .map(|slot_account_key| {
                SsoAllocationOutcome::Allocated(SsoAllocatedResource::BulletinAllowance {
                    slot_account_key,
                })
            }),
            SsoAllocatableResource::SmartContractAllowance(index) => {
                allocate_smart_contract_allowance(
                    services,
                    signing_host,
                    session,
                    calling_product_id,
                    index,
                    on_existing,
                )
                .await
                .map(|()| {
                    SsoAllocationOutcome::Allocated(SsoAllocatedResource::SmartContractAllowance)
                })
            }
            SsoAllocatableResource::AutoSigning => {
                let product_root_private_key = signing_host
                    .product_subtree_secret(calling_product_id)
                    .map_err(AllowanceAllocationError::Authority)?;
                let root_entropy = signing_host.root_entropy()?;
                let ring_vrf_domain_entropy =
                    derive_ring_vrf_domain_entropy(&root_entropy, calling_product_id)
                        .map_err(super::product_authority_error)
                        .map_err(AllowanceAllocationError::Authority)?;
                Ok(SsoAllocationOutcome::Allocated(
                    SsoAllocatedResource::AutoSigning {
                        product_root_private_key,
                        ring_vrf_domain_entropy,
                    },
                ))
            }
        }
    }

    async fn serve_resource_allocation(
        &self,
        cx: &SsoRequestContext,
        request: ResourceAllocationRequest,
    ) -> SsoReply<ResourceAllocationResponse> {
        let mut failures = Vec::new();
        let payload = async {
            let review = UserConfirmationReview::ResourceAllocation(ResourceAllocationReview {
                calling_product_id: request.calling_product_id.clone(),
                resources: request
                    .resources
                    .iter()
                    .map(public_allocatable_resource)
                    .collect(),
            });
            match self.services.platform.confirm_user_action(review).await {
                Ok(true) => {}
                Ok(false) => {
                    return Ok(vec![
                        SsoAllocationOutcome::Rejected;
                        request.resources.len()
                    ]);
                }
                Err(err) => return Err(format!("confirmation failed: {}", err.reason)),
            }

            self.signing_host
                .require_current_session(&cx.session)
                .map_err(|err| err.to_string())?;
            let mut outcomes = Vec::with_capacity(request.resources.len());
            for resource in request.resources {
                self.signing_host
                    .require_current_session(&cx.session)
                    .map_err(|err| err.to_string())?;
                let outcome = self
                    .allocate(
                        &cx.session,
                        &request.calling_product_id,
                        resource,
                        request.on_existing,
                    )
                    .await;
                self.signing_host
                    .require_current_session(&cx.session)
                    .map_err(|err| err.to_string())?;
                outcomes.push(outcome.unwrap_or_else(|err| {
                    let reason = err.to_string();
                    warn!(%reason, "resource allocation item failed");
                    failures.push(reason);
                    SsoAllocationOutcome::NotAvailable
                }));
            }
            Ok(outcomes)
        }
        .await;
        if let Err(reason) = &payload {
            warn!(%reason, "resource allocation request failed");
        }
        allocation_reply(payload, failures)
    }
}

fn allocation_reply(
    payload: Result<Vec<SsoAllocationOutcome>, String>,
    failures: Vec<String>,
) -> SsoReply<ResourceAllocationResponse> {
    let mut outcome = crate::host_logic::sso::messages::resource_allocation_outcome(&payload);
    if !failures.is_empty() {
        let details = failures.join("; ").replace(['\r', '\n'], " ");
        outcome.reason = Some(match outcome.reason {
            Some(summary) => format!("{summary}: {details}"),
            None => details,
        });
    }
    SsoReply::from(payload).with_outcome(outcome)
}

fn public_allocatable_resource(resource: &SsoAllocatableResource) -> api::AllocatableResource {
    match resource {
        SsoAllocatableResource::StatementStoreAllowance => {
            api::AllocatableResource::StatementStoreAllowance
        }
        SsoAllocatableResource::BulletinAllowance => api::AllocatableResource::BulletinAllowance,
        SsoAllocatableResource::SmartContractAllowance(index) => {
            api::AllocatableResource::SmartContractAllowance(index.clone())
        }
        SsoAllocatableResource::AutoSigning => api::AllocatableResource::AutoSigning,
    }
}

#[truapi_macros::sso_service]
impl SigningHostSsoService {
    /// Sign a payload or raw bytes with a product account.
    async fn sign(&self, cx: &SsoRequestContext, request: SignRequest) -> SignResponse {
        let payload = self.serve_sign(cx, request).await;
        if let Err(reason) = &payload {
            warn!(%reason, "sign request failed");
        }
        payload
    }

    /// Derive a contextual alias for a registered ring-VRF key.
    async fn get_account_alias(
        &self,
        cx: &SsoRequestContext,
        request: GetAccountAliasRequest,
    ) -> GetAccountAliasResponse {
        self.signing_host
            .account_alias(&cx.call, &cx.session, request)
            .await
    }

    /// Allocate SSO-backed resources for a product.
    async fn resource_allocation(
        &self,
        cx: &SsoRequestContext,
        request: ResourceAllocationRequest,
    ) -> ResourceAllocationResponse {
        self.serve_resource_allocation(cx, request).await
    }

    /// Build a signed transaction for a product account.
    async fn create_transaction(
        &self,
        cx: &SsoRequestContext,
        request: CreateTransactionRequest,
    ) -> CreateTransactionResponse {
        let CreateTransactionPayload::V1(payload) = request.payload;
        self.serve_create_transaction(
            cx,
            CreateTransactionReview::Product(payload.clone()),
            CreateTransactionAuthorityRequest::Product(payload),
        )
        .await
    }

    /// Build a signed transaction for the wallet's identity account.
    async fn create_transaction_with_legacy_account(
        &self,
        cx: &SsoRequestContext,
        request: CreateTransactionWithLegacyAccountRequest,
    ) -> CreateTransactionResponse {
        let CreateTransactionLegacyPayload::V1(payload) = request.payload;
        self.serve_create_transaction(
            cx,
            CreateTransactionReview::LegacyAccount(payload.clone()),
            CreateTransactionAuthorityRequest::IdentityAccount(payload),
        )
        .await
    }

    /// Sign raw data with a legacy account.
    async fn sign_raw_with_legacy_account(
        &self,
        cx: &SsoRequestContext,
        request: SignRawWithLegacyAccountRequest,
    ) -> SignRawWithLegacyAccountResponse {
        let public_request = api::HostSignRawWithLegacyAccountRequest {
            signer: product_public_key_to_address(request.account),
            payload: request.data.into(),
        };
        self.confirm(UserConfirmationReview::SignRaw(
            SignRawReview::LegacyAccount(public_request.clone()),
        ))
        .await?;
        self.signing_host
            .sign_raw(
                &cx.call,
                &cx.session,
                SignRawAuthorityRequest::LegacyAccount {
                    account: request.account,
                    request: public_request,
                },
            )
            .await
            .map(|response| response.signature)
            .map_err(|err| err.to_string())
    }

    /// Create a ring-VRF proof bound to a context and message.
    async fn create_account_proof(
        &self,
        cx: &SsoRequestContext,
        request: CreateAccountProofRequest,
    ) -> CreateAccountProofResponse {
        self.signing_host
            .create_proof(&cx.call, &cx.session, request)
            .await
    }

    /// Sign an RFC-0023 VRF transcript.
    async fn sign_vrf(&self, cx: &SsoRequestContext, request: SignVrfRequest) -> SignVrfResponse {
        self.signing_host
            .sign_vrf(
                &cx.call,
                &cx.session,
                request.calling_product_id,
                request.payload,
            )
            .await
            .map_err(|err| match err {
                AuthorityError::Disconnected => v01::HostAccountSignVrfError::NotConnected,
                AuthorityError::Rejected => v01::HostAccountSignVrfError::Rejected,
                AuthorityError::Cancelled(err) => v01::HostAccountSignVrfError::Unknown {
                    reason: err.to_string(),
                },
                AuthorityError::Unavailable { reason }
                | AuthorityError::NotSupported { reason }
                | AuthorityError::Unknown { reason } => {
                    v01::HostAccountSignVrfError::Unknown { reason }
                }
            })
    }

    /// Consent-free product hard-subtree public key.
    async fn product_subtree(
        &self,
        cx: &SsoRequestContext,
        request: ProductSubtreeRequest,
    ) -> ProductSubtreeResponse {
        self.signing_host
            .product_subtree_public_key(&cx.call, &cx.session, request.product_id)
            .await
            .map_err(|err| err.to_string())
    }

    /// Register a ring-VRF key owned by the calling product.
    async fn register_ring_vrf_key(
        &self,
        cx: &SsoRequestContext,
        request: RegisterRingVrfKeyRequest,
    ) -> RegisterRingVrfKeyResponse {
        self.signing_host
            .register_ring_vrf_key(&cx.call, &cx.session, request)
            .await
    }

    /// List registered ring-VRF keys.
    async fn list_ring_vrf_keys(
        &self,
        cx: &SsoRequestContext,
        request: ListRingVrfKeysRequest,
    ) -> ListRingVrfKeysResponse {
        self.signing_host
            .list_ring_vrf_keys(&cx.call, &cx.session, request)
            .await
    }

    /// Sign bytes directly with a registered ring-VRF key.
    async fn ring_vrf_sign(
        &self,
        cx: &SsoRequestContext,
        request: RingVrfSignRequest,
    ) -> RingVrfSignResponse {
        self.signing_host
            .ring_vrf_sign(&cx.call, &cx.session, request)
            .await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn allocation_transcript_includes_single_line_item_failures() {
        let answer = allocation_reply(
            Ok(vec![SsoAllocationOutcome::NotAvailable]),
            vec!["rpc\nfailed".to_string(), "provider\rdown".to_string()],
        )
        .finish("allocation-1");

        assert_eq!(answer.outcome.outcome, "not_available");
        assert_eq!(
            answer.outcome.reason.as_deref(),
            Some("Requested resource is not available: rpc failed; provider down")
        );
    }
}
