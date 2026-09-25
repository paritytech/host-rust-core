use super::*;
use crate::host_logic::sso::messages::{
    OnExistingAllowancePolicy, RemoteMessage, RemoteMessageData, ResourceAllocationRequest,
    SignRequest, SsoAllocationOutcome, v1,
};
use crate::runtime::authority::AutoSigningGrant;
use crate::runtime::signing_host::SigningHostSsoService;
use crate::runtime::sso_service::Dispatch;
use futures::executor::block_on;
use truapi::versioned::account::{
    HostAccountGetResponse, HostAccountListRingVrfKeysError, HostAccountListRingVrfKeysRequest,
    HostAccountListRingVrfKeysResponse, HostAccountSignVrfRequest, HostAccountSignVrfResponse,
};
use truapi::versioned::resource_allocation::HostRequestResourceAllocationError;
use truapi::versioned::signing::{
    HostCreateTransactionRequest, HostCreateTransactionResponse, HostSignPayloadError,
    HostSignPayloadRequest, HostSignPayloadResponse, HostSignPayloadWithLegacyAccountError,
    HostSignPayloadWithLegacyAccountRequest, HostSignRawWithLegacyAccountError,
    HostSignRawWithLegacyAccountRequest,
};
use truapi_platform::{
    AccountAccessReview, PermissionAuthorizationRequest, PermissionAuthorizationStatus,
    ResourceAllocationReview, SignPayloadReview, SignRawReview, SignVrfReview,
};

const TRUSTED_PRODUCTS: [&str; 12] = [
    "peopl.dot",
    "peopl.paseo",
    "peopl.testnet",
    "dim2.dot",
    "dim2.paseo",
    "dim2.testnet",
    "jollity.dot",
    "jollity.paseo",
    "jollity.testnet",
    "stash.dot",
    "stash.paseo",
    "stash.testnet",
];

fn signing_runtime_for_product(product_id: &str) -> (Arc<StubPlatform>, ProductRuntimeHost) {
    let platform = Arc::new(StubPlatform::default());
    let (services, authority) = signing_runtime_with_platform(platform.clone());
    block_on(authority.activate_local_session(ENTROPY.to_vec())).unwrap();
    (
        platform,
        product_runtime_for(services, authority, product_id),
    )
}

fn account(product_id: &str) -> v01::ProductAccountId {
    v01::ProductAccountId {
        dot_ns_identifier: product_id.to_string(),
        derivation_index: v01::DerivationIndex::Index(0),
    }
}

fn payload_request(product_id: &str) -> v01::HostSignPayloadRequest {
    v01::HostSignPayloadRequest {
        account: account(product_id),
        payload: crate::test_support::sign_payload_data(),
    }
}

fn raw_request(product_id: &str) -> v01::HostSignRawRequest {
    v01::HostSignRawRequest {
        account: account(product_id),
        payload: v01::RawPayload::Bytes {
            bytes: b"hello world".to_vec(),
        },
    }
}

fn review_counts(platform: &StubPlatform) -> (usize, usize, usize, usize) {
    (
        platform.remote_permission_requests.lock().unwrap().len(),
        platform.sign_payload_reviews.lock().unwrap().len(),
        platform.create_transaction_reviews.lock().unwrap().len(),
        platform.sign_raw_reviews.lock().unwrap().len(),
    )
}

#[test]
fn trusted_products_sign_payloads_without_confirmation() {
    let root = derive_root_keypair_from_entropy(&ENTROPY).unwrap();
    for product_id in TRUSTED_PRODUCTS {
        let (platform, runtime) = signing_runtime_for_product(product_id);
        let request = payload_request(product_id);
        let preimage = extrinsic_payload_preimage(&request.payload).unwrap();
        let HostSignPayloadResponse::V1(response) = block_on(
            runtime.sign_payload(&CallContext::default(), HostSignPayloadRequest::V1(request)),
        )
        .expect("trusted products sign their own payload without approval");

        let keypair = derive_product_keypair(&root, product_id, index_bytes(0)).unwrap();
        let signature = schnorrkel::Signature::from_bytes(&response.signature[1..]).unwrap();
        assert_eq!(
            (
                response.signature[0],
                keypair
                    .public
                    .verify_simple(SR25519_SIGNING_CONTEXT, &preimage, &signature)
                    .is_ok(),
                review_counts(&platform),
            ),
            (1, true, (0, 0, 0, 0)),
            "{product_id}",
        );
    }
}

#[test]
fn trusted_products_create_transactions_without_confirmation() {
    let root = derive_root_keypair_from_entropy(&ENTROPY).unwrap();
    for product_id in TRUSTED_PRODUCTS {
        let (platform, runtime) = signing_runtime_for_product(product_id);
        let request = v01::ProductAccountTxPayload {
            signer: account(product_id),
            ..tx_payload(0)
        };
        let HostCreateTransactionResponse::V1(response) = block_on(runtime.create_transaction(
            &CallContext::default(),
            HostCreateTransactionRequest::V1(request),
        ))
        .expect("trusted products create their own transaction without approval");

        let keypair = derive_product_keypair(&root, product_id, index_bytes(0)).unwrap();
        let (signer, signature, tail) = split_v4(&response.transaction);
        let signature = schnorrkel::Signature::from_bytes(&signature).unwrap();
        assert_eq!(
            (
                signer,
                tail,
                keypair
                    .public
                    .verify_simple(SR25519_SIGNING_CONTEXT, &[0, 0, 1, 2, 3], &signature)
                    .is_ok(),
                review_counts(&platform),
            ),
            (keypair.public.to_bytes(), vec![1, 0, 0], true, (0, 0, 0, 0)),
            "{product_id}",
        );
    }
}

#[test]
fn trusted_products_sign_watermarked_messages_without_confirmation() {
    let root = derive_root_keypair_from_entropy(&ENTROPY).unwrap();
    for product_id in TRUSTED_PRODUCTS {
        let (platform, runtime) = signing_runtime_for_product(product_id);
        let HostSignRawResponse::V1(response) = block_on(runtime.sign_raw(
            &CallContext::default(),
            HostSignRawRequest::V1(raw_request(product_id)),
        ))
        .expect("trusted products sign watermarked messages without approval");

        let keypair = derive_product_keypair(&root, product_id, index_bytes(0)).unwrap();
        let signature = schnorrkel::Signature::from_bytes(&response.signature).unwrap();
        assert_eq!(
            (
                keypair
                    .public
                    .verify_simple(
                        SR25519_SIGNING_CONTEXT,
                        b"<Bytes>hello world</Bytes>",
                        &signature,
                    )
                    .is_ok(),
                review_counts(&platform),
            ),
            (true, (0, 0, 0, 0)),
            "{product_id}",
        );
    }
}

#[test]
fn untrusted_callers_cannot_silently_sign_even_with_chain_submit_permission() {
    for (caller, owner) in [
        ("ordinary.paseo", "ordinary.paseo"),
        ("dim2-other.paseo", "dim2-other.paseo"),
        ("app.dim2.paseo", "app.dim2.paseo"),
        ("localhost", "dim2.paseo"),
    ] {
        let (platform, runtime) = signing_runtime_for_product(caller);
        let request = payload_request(owner);
        let result = block_on(runtime.sign_payload(
            &CallContext::default(),
            HostSignPayloadRequest::V1(request.clone()),
        ));
        assert_eq!(
            (
                result,
                platform.sign_payload_reviews.lock().unwrap().clone()
            ),
            (
                Err(CallError::Domain(HostSignPayloadError::V1(
                    v01::HostSignPayloadError::Rejected,
                ))),
                vec![SignPayloadReview::Product(request)],
            ),
            "{caller} signing for {owner}",
        );
    }
}

#[test]
fn trusted_signing_is_limited_to_the_callers_own_product_and_network() {
    let (_, authority) = signing_runtime();
    block_on(authority.activate_local_session(ENTROPY.to_vec())).unwrap();
    let session = authority.current_session().unwrap();
    for (caller, owner) in [
        ("dim2.paseo", "peopl.paseo"),
        ("dim2.paseo", "dim2.dot"),
        ("localhost", "dim2.paseo"),
    ] {
        assert_eq!(
            block_on(authority.auto_signing_status(&session, caller, &account(owner))),
            Ok(AutoSigningGrant::Absent),
        );
    }
}

#[test]
fn trusted_signing_ignores_a_stored_chain_submit_denial() {
    let (platform, runtime) = signing_runtime_for_product("dim2.paseo");
    request_resources(&runtime, &[v01::AllocatableResource::AutoSigning])
        .expect("trusted AutoSigning allocation succeeds");
    block_on(runtime.permissions_service().set_authorization_status(
        &PermissionAuthorizationRequest::Remote(v01::RemotePermissionRequest {
            permission: v01::RemotePermission::ChainSubmit,
        }),
        PermissionAuthorizationStatus::Denied,
    ))
    .unwrap();
    let transaction = v01::ProductAccountTxPayload {
        signer: account("dim2.paseo"),
        ..tx_payload(0)
    };
    let cx = CallContext::default();
    assert_eq!(
        (
            block_on(runtime.sign_payload(
                &cx,
                HostSignPayloadRequest::V1(payload_request("dim2.paseo")),
            ))
            .is_ok(),
            block_on(
                runtime.create_transaction(&cx, HostCreateTransactionRequest::V1(transaction))
            )
            .is_ok(),
            block_on(runtime.sign_raw(&cx, HostSignRawRequest::V1(raw_request("dim2.paseo"))))
                .is_ok(),
            review_counts(&platform),
        ),
        (true, true, true, (0, 0, 0, 0)),
    );
}

#[test]
fn trusted_products_cannot_authorize_a_stale_session() {
    let (_, authority) = signing_runtime();
    block_on(authority.activate_local_session(ENTROPY.to_vec())).unwrap();
    let stale_session = authority.current_session().unwrap();
    block_on(authority.disconnect());
    block_on(authority.activate_local_session(ENTROPY.to_vec())).unwrap();

    assert_eq!(
        block_on(authority.auto_signing_status(
            &stale_session,
            "dim2.paseo",
            &account("dim2.paseo"),
        )),
        Err(AuthorityError::Disconnected),
    );
}

#[test]
#[allow(deprecated)]
fn ordinary_products_still_confirm_unwatermarked_messages() {
    let (platform, runtime) = signing_runtime_for_product("ordinary.paseo");
    let request = raw_request("ordinary.paseo");
    let result = block_on(runtime.sign_raw_unwatermarked_deprecated(
        &CallContext::default(),
        HostSignRawRequest::V1(request.clone()),
    ));
    assert_eq!(
        (result, platform.sign_raw_reviews.lock().unwrap().clone()),
        (
            Err(CallError::Domain(HostSignRawError::V1(
                v01::HostSignPayloadError::Rejected,
            ))),
            vec![SignRawReview::Product {
                request,
                watermarked: false,
            }],
        ),
    );
}

#[test]
fn ordinary_products_still_confirm_legacy_signing() {
    let (platform, runtime) = signing_runtime_for_product("ordinary.paseo");
    let root = derive_root_keypair_from_entropy(&ENTROPY).unwrap();
    let keypair = derive_product_keypair(&root, "ordinary.paseo", index_bytes(0)).unwrap();
    let signer = subxt::utils::AccountId32(keypair.public.to_bytes()).to_string();
    let payload = v01::HostSignPayloadWithLegacyAccountRequest {
        signer: signer.clone(),
        payload: crate::test_support::sign_payload_data(),
    };
    let raw = v01::HostSignRawWithLegacyAccountRequest {
        signer,
        payload: raw_request("ordinary.paseo").payload,
    };
    let cx = CallContext::default();
    assert_eq!(
        (
            block_on(runtime.sign_payload_with_legacy_account(
                &cx,
                HostSignPayloadWithLegacyAccountRequest::V1(payload.clone()),
            )),
            block_on(runtime.sign_raw_with_legacy_account(
                &cx,
                HostSignRawWithLegacyAccountRequest::V1(raw.clone()),
            )),
            platform.sign_payload_reviews.lock().unwrap().clone(),
            platform.sign_raw_reviews.lock().unwrap().clone(),
        ),
        (
            Err(CallError::Domain(
                HostSignPayloadWithLegacyAccountError::V1(v01::HostSignPayloadError::Rejected,)
            )),
            Err(CallError::Domain(HostSignRawWithLegacyAccountError::V1(
                v01::HostSignPayloadError::Rejected,
            ))),
            vec![SignPayloadReview::LegacyAccount(payload)],
            vec![SignRawReview::LegacyAccount {
                request: raw,
                watermarked: true,
            }],
        ),
    );
}

#[test]
#[allow(deprecated)]
fn blessed_products_sign_deprecated_and_legacy_payloads_without_confirmation() {
    use truapi::versioned::signing::{
        HostCreateTransactionWithLegacyAccountRequest,
        HostCreateTransactionWithLegacyAccountResponse, HostSignPayloadWithLegacyAccountResponse,
        HostSignRawWithLegacyAccountResponse,
    };

    let root = derive_root_keypair_from_entropy(&ENTROPY).unwrap();
    for product_id in ["dim2.paseo", "peopl.dot", "stash.testnet"] {
        let platform = Arc::new(StubPlatform {
            permission_storage_error: Some("keychain locked"),
            ..StubPlatform::default()
        });
        let (services, authority) = signing_runtime_with_platform(platform.clone());
        block_on(authority.activate_local_session(ENTROPY.to_vec())).unwrap();
        let runtime = product_runtime_for(services, authority, product_id);
        let keypair = derive_product_keypair(&root, product_id, index_bytes(0)).unwrap();
        let signer = subxt::utils::AccountId32(keypair.public.to_bytes()).to_string();
        let cx = CallContext::default();
        let HostSignRawResponse::V1(raw) = block_on(runtime.sign_raw_unwatermarked_deprecated(
            &cx,
            HostSignRawRequest::V1(raw_request(product_id)),
        ))
        .unwrap();
        let payload = crate::test_support::sign_payload_data();
        let preimage = extrinsic_payload_preimage(&payload).unwrap();
        let HostSignPayloadWithLegacyAccountResponse::V1(legacy_payload) =
            block_on(runtime.sign_payload_with_legacy_account(
                &cx,
                HostSignPayloadWithLegacyAccountRequest::V1(
                    v01::HostSignPayloadWithLegacyAccountRequest {
                        signer: signer.clone(),
                        payload,
                    },
                ),
            ))
            .unwrap();
        let legacy_raw_request =
            HostSignRawWithLegacyAccountRequest::V1(v01::HostSignRawWithLegacyAccountRequest {
                signer,
                payload: raw_request(product_id).payload,
            });
        let HostSignRawWithLegacyAccountResponse::V1(legacy_raw) =
            block_on(runtime.sign_raw_with_legacy_account(&cx, legacy_raw_request.clone()))
                .unwrap();
        let HostSignRawWithLegacyAccountResponse::V1(legacy_unwatermarked) = block_on(
            runtime.sign_raw_unwatermarked_deprecated_with_legacy_account(&cx, legacy_raw_request),
        )
        .unwrap();
        let payload = tx_payload(0);
        let HostCreateTransactionWithLegacyAccountResponse::V1(transaction) =
            block_on(runtime.create_transaction_with_legacy_account(
                &cx,
                HostCreateTransactionWithLegacyAccountRequest::V1(v01::LegacyAccountTxPayload {
                    signer: keypair.public.to_bytes(),
                    genesis_hash: payload.genesis_hash,
                    call_data: payload.call_data,
                    extensions: payload.extensions,
                    tx_ext_version: payload.tx_ext_version,
                }),
            ))
            .unwrap();
        let (transaction_signer, transaction_signature, tail) = split_v4(&transaction.transaction);
        let verify = |signature: &[u8], message: &[u8]| {
            keypair
                .public
                .verify_simple(
                    SR25519_SIGNING_CONTEXT,
                    message,
                    &schnorrkel::Signature::from_bytes(signature).unwrap(),
                )
                .is_ok()
        };
        assert_eq!(
            (
                [
                    verify(&raw.signature, b"hello world"),
                    verify(&legacy_payload.signature[1..], &preimage),
                    verify(&legacy_raw.signature, b"<Bytes>hello world</Bytes>"),
                    verify(&legacy_unwatermarked.signature, b"hello world"),
                    verify(&transaction_signature, &[0, 0, 1, 2, 3])
                ],
                transaction_signer,
                tail,
                review_counts(&platform),
            ),
            (
                [true; 5],
                keypair.public.to_bytes(),
                vec![1, 0, 0],
                (0, 0, 0, 0)
            ),
            "{product_id}",
        );
    }
}

#[test]
fn blessed_products_sign_vrf_without_allocating_auto_signing() {
    let root = derive_root_keypair_from_entropy(&ENTROPY).unwrap();
    for product_id in ["dim2.paseo", "peopl.dot", "stash.testnet"] {
        let (platform, runtime) = signing_runtime_for_product(product_id);
        let HostAccountSignVrfResponse::V1(signature) = block_on(runtime.sign_vrf(
            &CallContext::default(),
            HostAccountSignVrfRequest::V1(vrf_request(product_id)),
        ))
        .unwrap();
        let mut transcript = merlin::Transcript::new(b"pop:autosigning");
        transcript.append_message(b"round", &[1]);
        let keypair = derive_product_keypair(&root, product_id, index_bytes(0)).unwrap();
        assert_eq!(
            (
                keypair
                    .public
                    .vrf_verify(
                        transcript,
                        &schnorrkel::vrf::VRFPreOut::from_bytes(&signature.pre_output).unwrap(),
                        &schnorrkel::vrf::VRFProof::from_bytes(&signature.proof).unwrap()
                    )
                    .is_ok(),
                platform.sign_vrf_reviews.lock().unwrap().clone(),
                platform.resource_allocation_reviews.lock().unwrap().clone(),
            ),
            (true, vec![], vec![]),
        );
    }
}

#[test]
fn blessed_vrf_access_to_a_foreign_account_requires_an_authenticated_caller() {
    let product_id = "dim2.paseo";
    let request = vrf_request("other.paseo");
    let (platform, runtime) = signing_runtime_for_product(product_id);
    let HostAccountSignVrfResponse::V1(signature) = block_on(runtime.sign_vrf(
        &CallContext::default(),
        HostAccountSignVrfRequest::V1(request.clone()),
    ))
    .unwrap();
    let root = derive_root_keypair_from_entropy(&ENTROPY).unwrap();
    let keypair = derive_product_keypair(&root, "other.paseo", index_bytes(0)).unwrap();
    let mut transcript = merlin::Transcript::new(b"pop:autosigning");
    transcript.append_message(b"round", &[1]);
    assert_eq!(
        (
            keypair
                .public
                .vrf_verify(
                    transcript,
                    &schnorrkel::vrf::VRFPreOut::from_bytes(&signature.pre_output).unwrap(),
                    &schnorrkel::vrf::VRFProof::from_bytes(&signature.proof).unwrap(),
                )
                .is_ok(),
            platform.sign_vrf_reviews.lock().unwrap().clone()
        ),
        (true, vec![]),
    );

    let (_, authority) = signing_runtime_with_platform(platform.clone());
    block_on(authority.activate_local_session(ENTROPY.to_vec())).unwrap();
    let service = SigningHostSsoService::new(authority);
    let Dispatch::Response(answer) = block_on(service.answer(RemoteMessage::request(
        "relayed-foreign-vrf".to_string(),
        ProductRequest {
            calling_product_id: product_id.to_string(),
            payload: request.clone(),
        },
    ))) else {
        panic!("expected VRF response")
    };
    let RemoteMessageData::V1(v1::RemoteMessage::SignVrfResponse(response)) = answer.message.data
    else {
        panic!("expected VRF signing response")
    };
    assert_eq!(
        (
            response.payload,
            platform.sign_vrf_reviews.lock().unwrap().clone()
        ),
        (
            Err(v01::HostAccountSignVrfError::Rejected),
            vec![SignVrfReview {
                calling_product_id: product_id.to_string(),
                request,
            }]
        ),
    );
}

#[test]
#[allow(deprecated)]
fn blessed_legacy_identity_signing_skips_confirmation_but_ordinary_signing_does_not() {
    use truapi::versioned::signing::{
        HostCreateTransactionWithLegacyAccountRequest,
        HostCreateTransactionWithLegacyAccountResponse, HostSignRawWithLegacyAccountResponse,
    };

    let identity = derive_identity_keypair(&ENTROPY, TEST_NETWORK_SUFFIX).unwrap();
    for (product_id, blessed) in [("dim2.paseo", true), ("ordinary.paseo", false)] {
        let (platform, runtime) = signing_runtime_for_product(product_id);
        let request =
            HostSignRawWithLegacyAccountRequest::V1(v01::HostSignRawWithLegacyAccountRequest {
                signer: subxt::utils::AccountId32(identity.public.to_bytes()).to_string(),
                payload: raw_request(product_id).payload,
            });
        let cx = CallContext::default();
        let mut signatures = Vec::new();
        for watermarked in [false, true] {
            let result = if watermarked {
                block_on(runtime.sign_raw_with_legacy_account(&cx, request.clone()))
            } else {
                block_on(
                    runtime.sign_raw_unwatermarked_deprecated_with_legacy_account(
                        &cx,
                        request.clone(),
                    ),
                )
            };
            signatures.push(
                result
                    .map(|HostSignRawWithLegacyAccountResponse::V1(response)| {
                        identity
                            .public
                            .verify_simple(
                                SR25519_SIGNING_CONTEXT,
                                if watermarked {
                                    b"<Bytes>hello world</Bytes>"
                                } else {
                                    b"hello world"
                                },
                                &schnorrkel::Signature::from_bytes(&response.signature).unwrap(),
                            )
                            .is_ok()
                    })
                    .map_err(|_| ()),
            );
        }
        let payload = tx_payload(0);
        let transaction = block_on(runtime.create_transaction_with_legacy_account(
            &cx,
            HostCreateTransactionWithLegacyAccountRequest::V1(v01::LegacyAccountTxPayload {
                signer: identity.public.to_bytes(),
                genesis_hash: payload.genesis_hash,
                call_data: payload.call_data,
                extensions: payload.extensions,
                tx_ext_version: payload.tx_ext_version,
            }),
        ))
        .map(
            |HostCreateTransactionWithLegacyAccountResponse::V1(response)| {
                let (signer, signature, _) = split_v4(&response.transaction);
                signer == identity.public.to_bytes()
                    && identity
                        .public
                        .verify_simple(
                            SR25519_SIGNING_CONTEXT,
                            &[0, 0, 1, 2, 3],
                            &schnorrkel::Signature::from_bytes(&signature).unwrap(),
                        )
                        .is_ok()
            },
        )
        .map_err(|_| ());
        let expected = if blessed { Ok(true) } else { Err(()) };
        assert_eq!(
            (
                signatures,
                transaction,
                platform.sign_raw_reviews.lock().unwrap().len(),
                platform.create_transaction_reviews.lock().unwrap().len()
            ),
            (
                vec![expected; 2],
                expected,
                if blessed { 0 } else { 2 },
                if blessed { 0 } else { 1 }
            )
        );
    }
}

#[test]
fn a_relayed_trusted_account_still_requires_confirmation() {
    let platform = Arc::new(StubPlatform::default());
    let (_, authority) = signing_runtime_with_platform(platform.clone());
    block_on(authority.activate_local_session(ENTROPY.to_vec())).unwrap();
    let service = SigningHostSsoService::new(authority);
    let request = payload_request("dim2.paseo");
    let message = RemoteMessage::request(
        "trusted-signing".to_string(),
        SignRequest::Payload(Box::new(request.clone())),
    );
    let Dispatch::Response(answer) = block_on(service.answer(message)) else {
        panic!("expected signing response")
    };
    let RemoteMessageData::V1(v1::RemoteMessage::SignResponse(response)) = answer.message.data
    else {
        panic!("expected payload signing response")
    };
    assert_eq!(
        (
            response.payload,
            platform.sign_payload_reviews.lock().unwrap().clone(),
        ),
        (
            Err("Rejected".to_string()),
            vec![SignPayloadReview::Product(request)],
        ),
    );
}

#[test]
fn a_relayed_blessed_vrf_claim_still_requires_a_grant_or_confirmation() {
    for allocated in [false, true] {
        let platform = Arc::new(StubPlatform::default());
        let (_, authority) = signing_runtime_with_platform(platform.clone());
        block_on(authority.activate_local_session(ENTROPY.to_vec())).unwrap();
        let session = authority.current_session().unwrap();
        if allocated {
            authority
                .grant_auto_signing(&session, "dim2.paseo")
                .unwrap();
        }
        let service = SigningHostSsoService::new(authority);
        let request = vrf_request("dim2.paseo");
        let message = RemoteMessage::request(
            "relayed-vrf".to_string(),
            ProductRequest {
                calling_product_id: "dim2.paseo".to_string(),
                payload: request.clone(),
            },
        );
        let Dispatch::Response(answer) = block_on(service.answer(message)) else {
            panic!("expected VRF response")
        };
        let RemoteMessageData::V1(v1::RemoteMessage::SignVrfResponse(response)) =
            answer.message.data
        else {
            panic!("expected VRF signing response")
        };
        assert_eq!(
            (
                response.payload.map(|_| ()),
                platform.sign_vrf_reviews.lock().unwrap().clone()
            ),
            if allocated {
                (Ok(()), vec![])
            } else {
                (
                    Err(v01::HostAccountSignVrfError::Rejected),
                    vec![SignVrfReview {
                        calling_product_id: "dim2.paseo".to_string(),
                        request,
                    }],
                )
            },
        );
    }
}

fn request_resources(
    runtime: &ProductRuntimeHost,
    resources: &[v01::AllocatableResource],
) -> Result<HostRequestResourceAllocationResponse, CallError<HostRequestResourceAllocationError>> {
    block_on(ResourceAllocation::request(
        runtime,
        &CallContext::default(),
        HostRequestResourceAllocationRequest::V1(v01::HostRequestResourceAllocationRequest {
            resources: resources.to_vec(),
        }),
    ))
}

fn rejected_allocation() -> CallError<HostRequestResourceAllocationError> {
    CallError::Domain(HostRequestResourceAllocationError::V1(
        v01::ResourceAllocationError::Unknown {
            reason: "User rejected resource allocation".to_string(),
        },
    ))
}

#[test]
fn trusted_auto_signing_allocation_records_a_usable_grant_without_confirmation() {
    let root = derive_root_keypair_from_entropy(&ENTROPY).unwrap();
    for product_id in TRUSTED_PRODUCTS {
        let (platform, runtime) = signing_runtime_for_product(product_id);
        assert_eq!(
            (
                request_resources(&runtime, &[v01::AllocatableResource::AutoSigning]),
                platform.resource_allocation_reviews.lock().unwrap().clone(),
            ),
            (
                Ok(HostRequestResourceAllocationResponse::V1(
                    v01::HostRequestResourceAllocationResponse {
                        outcomes: vec![v01::AllocationOutcome::Allocated],
                    },
                )),
                vec![],
            ),
            "{product_id}",
        );

        let HostAccountSignVrfResponse::V1(signature) = block_on(runtime.sign_vrf(
            &CallContext::default(),
            HostAccountSignVrfRequest::V1(vrf_request(product_id)),
        ))
        .expect("the allocated grant permits VRF signing without confirmation");
        let mut transcript = merlin::Transcript::new(b"pop:autosigning");
        transcript.append_message(b"round", &[1]);
        let keypair = derive_product_keypair(&root, product_id, index_bytes(0)).unwrap();
        keypair
            .public
            .vrf_verify(
                transcript,
                &schnorrkel::vrf::VRFPreOut::from_bytes(&signature.pre_output).unwrap(),
                &schnorrkel::vrf::VRFProof::from_bytes(&signature.proof).unwrap(),
            )
            .expect("the allocated product key signs the requested VRF transcript");
        assert_eq!(
            (
                platform.sign_vrf_reviews.lock().unwrap().clone(),
                platform.sent_rpc.lock().unwrap().clone(),
            ),
            (vec![], vec![]),
            "{product_id}",
        );
    }
}

#[test]
fn untrusted_products_still_confirm_auto_signing_allocation() {
    for product_id in [
        "ordinary.paseo",
        "dim2-other.paseo",
        "app.dim2.paseo",
        "localhost",
    ] {
        let (platform, runtime) = signing_runtime_for_product(product_id);
        let resources = vec![v01::AllocatableResource::AutoSigning];
        assert_eq!(
            (
                request_resources(&runtime, &resources),
                platform.resource_allocation_reviews.lock().unwrap().clone(),
            ),
            (
                Err(rejected_allocation()),
                vec![ResourceAllocationReview {
                    calling_product_id: product_id.to_string(),
                    resources,
                }],
            ),
        );
    }
}

#[test]
fn ordinary_resource_allocations_require_consent_and_leave_no_partial_grant() {
    use v01::AllocatableResource::{
        AutoSigning, BulletinAllowance, SmartContractAllowance, StatementStoreAllowance,
    };

    for resources in [
        vec![StatementStoreAllowance],
        vec![BulletinAllowance],
        vec![SmartContractAllowance(v01::DerivationIndex::Index(0))],
        vec![AutoSigning, StatementStoreAllowance],
        vec![BulletinAllowance, AutoSigning],
    ] {
        let platform = Arc::new(StubPlatform::default());
        let (services, authority) = signing_runtime_with_platform(platform.clone());
        block_on(authority.activate_local_session(ENTROPY.to_vec())).unwrap();
        let runtime = product_runtime_for(services, authority.clone(), "ordinary.paseo");
        assert_eq!(
            (
                request_resources(&runtime, &resources),
                platform.resource_allocation_reviews.lock().unwrap().clone(),
            ),
            (
                Err(rejected_allocation()),
                vec![ResourceAllocationReview {
                    calling_product_id: "ordinary.paseo".to_string(),
                    resources,
                }],
            ),
        );
        assert!(
            authority
                .local_grants
                .lock()
                .unwrap()
                .auto_signing_grants
                .is_empty(),
            "declining the batch must not allocate AutoSigning"
        );
    }
}

#[test]
fn a_pairing_host_still_confirms_ordinary_auto_signing_allocation() {
    let platform = Arc::new(StubPlatform::default());
    let runtime = ProductRuntimeHost::new(
        platform.clone(),
        crate::test_support::runtime_config("ordinary.paseo"),
        test_spawner(),
    );
    runtime
        .test_session_state()
        .set_session(crate::test_support::sso_session_info());
    let resources = vec![v01::AllocatableResource::AutoSigning];
    assert_eq!(
        (
            request_resources(&runtime, &resources),
            platform.resource_allocation_reviews.lock().unwrap().clone(),
            platform.sent_rpc.lock().unwrap().clone(),
        ),
        (
            Err(rejected_allocation()),
            vec![ResourceAllocationReview {
                calling_product_id: "ordinary.paseo".to_string(),
                resources,
            }],
            vec![],
        ),
    );
}

#[test]
fn blessed_empty_allocation_needs_no_confirmation() {
    let (platform, runtime) = signing_runtime_for_product("dim2.paseo");
    assert_eq!(
        (
            request_resources(&runtime, &[]),
            platform.resource_allocation_reviews.lock().unwrap().clone()
        ),
        (
            Ok(HostRequestResourceAllocationResponse::V1(
                v01::HostRequestResourceAllocationResponse { outcomes: vec![] }
            )),
            vec![]
        ),
    );
}

#[test]
fn blessed_pairing_frontend_reaches_the_signer_without_confirmation() {
    use crate::host_logic::sso::messages::Response;
    use crate::test_support::{sso_success_response_script, submitted_remote_messages};

    let session = crate::test_support::sso_session_info();
    let request_id = "blessed-frontend";
    let responses = [
        v1::RemoteMessage::ResourceAllocationResponse(Response {
            responding_to: request_id.to_string(),
            payload: Ok(vec![SsoAllocationOutcome::NotAvailable; 4]),
        }),
        v1::RemoteMessage::ProductSubtreeResponse(Response {
            responding_to: request_id.to_string(),
            payload: Err("signer unavailable".to_string()),
        }),
        v1::RemoteMessage::SignVrfResponse(Response {
            responding_to: request_id.to_string(),
            payload: Err(v01::HostAccountSignVrfError::Rejected),
        }),
    ];
    for (index, response) in responses.into_iter().enumerate() {
        let platform = Arc::new(StubPlatform {
            product_subtree_denied: true,
            sso_response_script: Some(sso_success_response_script(
                &session,
                RemoteMessage {
                    message_id: "signer-response".to_string(),
                    data: RemoteMessageData::V1(response),
                },
            )),
            ..StubPlatform::default()
        });
        let runtime = ProductRuntimeHost::new(
            platform.clone(),
            crate::test_support::runtime_config("dim2.paseo"),
            test_spawner(),
        );
        runtime.test_session_state().set_session(session.clone());
        let mut cx = CallContext::with_request_id(request_id.to_string());
        cx.set_timeout(std::time::Duration::from_secs(5));
        let expected_message = match index {
            0 => {
                assert_eq!(
                    block_on(ResourceAllocation::request(
                        &runtime,
                        &cx,
                        HostRequestResourceAllocationRequest::V1(
                            v01::HostRequestResourceAllocationRequest {
                                resources: vec![
                                    v01::AllocatableResource::AutoSigning,
                                    v01::AllocatableResource::StatementStoreAllowance,
                                    v01::AllocatableResource::BulletinAllowance,
                                    v01::AllocatableResource::SmartContractAllowance(
                                        v01::DerivationIndex::Index(0)
                                    ),
                                ],
                            }
                        ),
                    )),
                    Ok(HostRequestResourceAllocationResponse::V1(
                        v01::HostRequestResourceAllocationResponse {
                            outcomes: vec![v01::AllocationOutcome::NotAvailable; 4],
                        }
                    )),
                );
                "resource_allocation"
            }
            1 => {
                assert!(
                    block_on(runtime.get_account(
                        &cx,
                        HostAccountGetRequest::V1(v01::HostAccountGetRequest {
                            product_account_id: account("dim2.paseo"),
                        })
                    ))
                    .is_err()
                );
                "product_subtree"
            }
            _ => {
                assert!(
                    block_on(runtime.sign_vrf(
                        &cx,
                        HostAccountSignVrfRequest::V1(vrf_request("other.paseo"))
                    ))
                    .is_err()
                );
                "sign_vrf"
            }
        };
        let messages = submitted_remote_messages(&platform, &session);
        assert_eq!(
            (
                messages.iter().map(RemoteMessage::name).collect::<Vec<_>>(),
                platform.resource_allocation_reviews.lock().unwrap().clone(),
                platform.product_subtree_reviews.lock().unwrap().clone(),
                platform.sign_vrf_reviews.lock().unwrap().clone(),
            ),
            (vec![expected_message], vec![], vec![], vec![]),
        );
    }
}

#[test]
fn a_relayed_auto_signing_delegation_request_requires_confirmation() {
    let platform = Arc::new(StubPlatform::default());
    let (_, authority) = signing_runtime_with_platform(platform.clone());
    block_on(authority.activate_local_session(ENTROPY.to_vec())).unwrap();
    let service = SigningHostSsoService::new(authority);
    let resources = vec![v01::AllocatableResource::AutoSigning];
    let message = RemoteMessage::request(
        "trusted-auto-signing".to_string(),
        ResourceAllocationRequest {
            calling_product_id: "dim2.paseo".to_string(),
            resources: resources.clone(),
            on_existing: OnExistingAllowancePolicy::Ignore,
        },
    );
    let Dispatch::Response(answer) = block_on(service.answer(message)) else {
        panic!("expected allocation response")
    };
    let RemoteMessageData::V1(v1::RemoteMessage::ResourceAllocationResponse(response)) =
        answer.message.data
    else {
        panic!("expected resource allocation response")
    };
    assert_eq!(
        (
            response.payload,
            platform.resource_allocation_reviews.lock().unwrap().clone(),
        ),
        (
            Ok(vec![SsoAllocationOutcome::Rejected]),
            vec![ResourceAllocationReview {
                calling_product_id: "dim2.paseo".to_string(),
                resources,
            }],
        ),
    );
}

fn read_account(
    runtime: &ProductRuntimeHost,
    owner: &str,
) -> Result<HostAccountGetResponse, CallError<HostAccountGetError>> {
    block_on(runtime.get_account(
        &CallContext::default(),
        HostAccountGetRequest::V1(v01::HostAccountGetRequest {
            product_account_id: account(owner),
        }),
    ))
}

fn list_ring_keys(
    runtime: &ProductRuntimeHost,
    owner: &str,
) -> Result<HostAccountListRingVrfKeysResponse, CallError<HostAccountListRingVrfKeysError>> {
    block_on(runtime.list_ring_vrf_keys(
        &CallContext::default(),
        HostAccountListRingVrfKeysRequest::V1(v01::HostAccountListRingVrfKeysRequest {
            owner: owner.to_string(),
            disclosure: v01::RingVrfKeyDisclosure::PublicKey,
        }),
    ))
}

#[test]
fn trusted_products_read_foreign_accounts_without_confirmation() {
    let root = derive_root_keypair_from_entropy(&ENTROPY).unwrap();
    for product_id in TRUSTED_PRODUCTS.into_iter().chain([" DIM2.PASEO "]) {
        let (platform, runtime) = signing_runtime_for_product(product_id);
        let keypair = derive_product_keypair(&root, "other.paseo", index_bytes(0)).unwrap();
        assert_eq!(
            (
                read_account(&runtime, " OTHER.PASEO "),
                platform.account_access_reviews.lock().unwrap().clone(),
            ),
            (
                Ok(HostAccountGetResponse::V1(v01::HostAccountGetResponse {
                    account: v01::ProductAccount {
                        public_key: keypair.public.to_bytes().to_vec(),
                    },
                })),
                vec![],
            ),
            "{product_id}",
        );
    }
}

#[test]
fn a_trusted_product_lists_another_products_registered_ring_keys_without_confirmation() {
    let platform = Arc::new(StubPlatform::default());
    let (services, authority) =
        signing_runtime_with_ring_resolver(platform.clone(), full_person_ring_resolver());
    block_on(authority.activate_local_session(ENTROPY.to_vec())).unwrap();
    register_full_person_key(
        &authority,
        &authority.current_session().unwrap(),
        &full_person_ring_location(),
    );
    let owner = product_runtime_for(services.clone(), authority.clone(), "peopl.dot");
    let expected = list_ring_keys(&owner, "peopl.dot").unwrap();
    let HostAccountListRingVrfKeysResponse::V1(keys) = &expected;
    assert!(!keys.is_empty(), "the fixture must expose registered keys");
    let caller = product_runtime_for(services, authority, " DIM2.DOT ");

    assert_eq!(
        (
            list_ring_keys(&caller, " PEOPL.DOT "),
            platform.account_access_reviews.lock().unwrap().clone(),
        ),
        (Ok(expected), vec![]),
    );
}

#[test]
fn untrusted_products_still_confirm_foreign_account_access() {
    for caller in [
        "ordinary.dot",
        "dim2-other.dot",
        "app.dim2.dot",
        "localhost",
    ] {
        let (platform, runtime) = signing_runtime_for_product(caller);
        assert_eq!(
            (
                read_account(&runtime, "peopl.dot"),
                platform.account_access_reviews.lock().unwrap().clone(),
            ),
            (
                Err(CallError::Domain(HostAccountGetError::V1(
                    v01::HostAccountGetError::Rejected
                ))),
                vec![AccountAccessReview {
                    requesting_product_id: caller.to_string(),
                    target_product_id: "peopl.dot".to_string(),
                }],
            ),
        );
    }
}

#[test]
fn untrusted_products_still_confirm_listing_foreign_ring_keys() {
    for caller in [
        "ordinary.dot",
        "dim2-other.dot",
        "app.dim2.dot",
        "localhost",
    ] {
        let (platform, runtime) = signing_runtime_for_product(caller);
        assert_eq!(
            (
                list_ring_keys(&runtime, "peopl.dot"),
                platform.account_access_reviews.lock().unwrap().clone(),
            ),
            (
                Err(CallError::Domain(HostAccountListRingVrfKeysError::V1(
                    v01::HostAccountListRingVrfKeysError::Rejected,
                ))),
                vec![AccountAccessReview {
                    requesting_product_id: caller.to_string(),
                    target_product_id: "peopl.dot".to_string(),
                }],
            ),
        );
    }
}

#[test]
fn trusted_account_access_ignores_stored_denials() {
    for denied_bare in [false, true] {
        let platform = Arc::new(StubPlatform::default());
        let (services, authority) =
            signing_runtime_with_ring_resolver(platform.clone(), full_person_ring_resolver());
        block_on(authority.activate_local_session(ENTROPY.to_vec())).unwrap();
        register_full_person_key(
            &authority,
            &authority.current_session().unwrap(),
            &full_person_ring_location(),
        );
        let owner = product_runtime_for(services.clone(), authority.clone(), "peopl.dot");
        let expected_account = read_account(&owner, "peopl.dot").unwrap();
        let expected_keys = list_ring_keys(&owner, "peopl.dot").unwrap();
        let runtime = product_runtime_for(services, authority, "dim2.dot");
        for (caller, target, bare) in [("dim2", "peopl", true), ("dim2.dot", "peopl.dot", false)] {
            block_on(crate::host_logic::permissions::set_account_access_status(
                platform.as_ref(),
                caller,
                target,
                if bare == denied_bare {
                    PermissionAuthorizationStatus::Denied
                } else {
                    PermissionAuthorizationStatus::Authorized
                },
            ))
            .unwrap();
        }
        assert_eq!(
            (
                read_account(&runtime, "peopl.dot"),
                list_ring_keys(&runtime, "peopl.dot"),
                platform.account_access_reviews.lock().unwrap().clone(),
            ),
            (Ok(expected_account), Ok(expected_keys), vec![]),
            "bare denial: {denied_bare}",
        );
    }
}

#[test]
fn jollity_setup_ignores_old_denials_without_non_device_prompts() {
    let root = derive_root_keypair_from_entropy(&ENTROPY).unwrap();
    for suffix in ["testnet", "paseo"] {
        let caller = format!("jollity.{suffix}");
        let owner = format!("dim2.{suffix}");
        for storage_error in [None, Some("permission storage must not be read")] {
            let platform = Arc::new(StubPlatform {
                permission_storage_error: storage_error,
                ..StubPlatform::default()
            });
            let (services, authority) = signing_runtime_with_platform(platform.clone());
            block_on(authority.activate_local_session(ENTROPY.to_vec())).unwrap();
            let runtime = product_runtime_for(services, authority, &caller);
            for (requester, target) in [("jollity", "dim2"), (caller.as_str(), owner.as_str())] {
                block_on(crate::host_logic::permissions::set_account_access_status(
                    platform.as_ref(),
                    requester,
                    target,
                    PermissionAuthorizationStatus::Denied,
                ))
                .unwrap();
            }
            block_on(runtime.set_permission_authorization_status(
                PermissionAuthorizationRequest::Remote(v01::RemotePermissionRequest {
                    permission: v01::RemotePermission::ChainSubmit,
                }),
                PermissionAuthorizationStatus::Denied,
            ))
            .unwrap();
            let stored = platform.local_storage.lock().unwrap().clone();
            let keypair = derive_product_keypair(&root, &owner, index_bytes(0)).unwrap();
            let cx = CallContext::default();
            assert_eq!(
                (
                    read_account(&runtime, &owner),
                    request_resources(&runtime, &[v01::AllocatableResource::AutoSigning]),
                    block_on(
                        runtime.sign_payload(
                            &cx,
                            HostSignPayloadRequest::V1(payload_request(&caller))
                        )
                    )
                    .is_ok(),
                    block_on(
                        runtime.sign_vrf(&cx, HostAccountSignVrfRequest::V1(vrf_request(&owner)))
                    )
                    .is_ok(),
                    review_counts(&platform),
                    platform.account_access_reviews.lock().unwrap().clone(),
                    platform.resource_allocation_reviews.lock().unwrap().clone(),
                    platform.sign_vrf_reviews.lock().unwrap().clone(),
                    platform.local_storage.lock().unwrap().clone(),
                ),
                (
                    Ok(HostAccountGetResponse::V1(v01::HostAccountGetResponse {
                        account: v01::ProductAccount {
                            public_key: keypair.public.to_bytes().to_vec()
                        }
                    })),
                    Ok(HostRequestResourceAllocationResponse::V1(
                        v01::HostRequestResourceAllocationResponse {
                            outcomes: vec![v01::AllocationOutcome::Allocated]
                        }
                    )),
                    true,
                    true,
                    (0, 0, 0, 0),
                    vec![],
                    vec![],
                    vec![],
                    stored,
                ),
                "{caller}, storage error: {storage_error:?}",
            );
        }
    }
}

#[test]
fn untrusted_account_access_fails_closed_when_permission_storage_cannot_be_read() {
    let platform = Arc::new(StubPlatform {
        permission_storage_error: Some("keychain locked"),
        ..StubPlatform::default()
    });
    let (services, authority) = signing_runtime_with_platform(platform.clone());
    block_on(authority.activate_local_session(ENTROPY.to_vec())).unwrap();
    let runtime = product_runtime_for(services, authority, "ordinary.dot");
    let reason = "permission storage failed: GenericError { reason: \"keychain locked\" }";
    assert_eq!(
        (
            read_account(&runtime, "peopl.dot"),
            list_ring_keys(&runtime, "peopl.dot"),
            platform.account_access_reviews.lock().unwrap().clone(),
        ),
        (
            Err(CallError::HostFailure {
                reason: reason.to_string()
            }),
            Err(CallError::Domain(HostAccountListRingVrfKeysError::V1(
                v01::HostAccountListRingVrfKeysError::Unknown {
                    reason: reason.to_string()
                },
            ))),
            vec![],
        ),
    );
}

#[test]
fn trusted_account_access_and_signing_do_not_read_permission_storage() {
    let platform = Arc::new(StubPlatform {
        permission_storage_error: Some("permission storage must not be read"),
        ..StubPlatform::default()
    });
    let (services, authority) =
        signing_runtime_with_ring_resolver(platform.clone(), full_person_ring_resolver());
    block_on(authority.activate_local_session(ENTROPY.to_vec())).unwrap();
    register_full_person_key(
        &authority,
        &authority.current_session().unwrap(),
        &full_person_ring_location(),
    );
    let owner = product_runtime_for(services.clone(), authority.clone(), "peopl.dot");
    let expected_account = read_account(&owner, "peopl.dot").unwrap();
    let expected_keys = list_ring_keys(&owner, "peopl.dot").unwrap();
    let runtime = product_runtime_for(services, authority, "dim2.dot");
    let cx = CallContext::default();
    assert_eq!(
        (
            read_account(&runtime, "peopl.dot"),
            list_ring_keys(&runtime, "peopl.dot"),
            block_on(
                runtime.sign_payload(&cx, HostSignPayloadRequest::V1(payload_request("dim2.dot")),)
            )
            .is_ok(),
            block_on(runtime.create_transaction(
                &cx,
                HostCreateTransactionRequest::V1(v01::ProductAccountTxPayload {
                    signer: account("dim2.dot"),
                    ..tx_payload(0)
                },)
            ))
            .is_ok(),
            block_on(runtime.sign_raw(&cx, HostSignRawRequest::V1(raw_request("dim2.dot"))))
                .is_ok(),
            review_counts(&platform),
            platform.account_access_reviews.lock().unwrap().clone(),
        ),
        (
            Ok(expected_account),
            Ok(expected_keys),
            true,
            true,
            true,
            (0, 0, 0, 0),
            vec![]
        ),
    );
}
