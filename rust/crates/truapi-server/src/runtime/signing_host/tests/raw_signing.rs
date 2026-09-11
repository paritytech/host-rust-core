//! Signature and consent regression coverage, including the deprecated APIs.
#![allow(deprecated)]

use super::*;
use crate::host_logic::sso::messages::{
    RemoteMessage, RemoteMessageData, SignRawWithLegacyAccountRequest, SignRequest, v1,
};
use crate::runtime::signing_host::sso_service::SigningHostSsoService;
use crate::runtime::sso_service::Dispatch;
use parity_scale_codec::{Decode, Encode};
use truapi::versioned::signing::{
    HostSignRawWithLegacyAccountRequest, HostSignRawWithLegacyAccountResponse,
};

#[test]
fn signing_apis_preserve_exact_bytes_and_watermark_semantics() {
    let (services, activation) = signing_runtime();
    futures::executor::block_on(activation.activate_local_session(ENTROPY.to_vec())).unwrap();
    let identity = derive_identity_keypair(&ENTROPY, TEST_NETWORK_SUFFIX).unwrap();
    let root = derive_root_keypair_from_entropy(&ENTROPY).unwrap();
    let product = derive_product_keypair(&root, "myapp.dot", index_bytes(0)).unwrap();
    let runtime = product_runtime(services, activation);
    let cx = CallContext::default();
    let alias = vec![0x11; 32];
    let payloads = [
        (
            v01::RawPayload::Bytes {
                bytes: alias.clone(),
            },
            alias,
        ),
        (v01::RawPayload::Bytes { bytes: vec![] }, vec![]),
        (
            v01::RawPayload::Payload {
                payload: "0x0102".into(),
            },
            vec![1, 2],
        ),
        (
            v01::RawPayload::Payload {
                payload: "hello".into(),
            },
            b"hello".to_vec(),
        ),
        (
            v01::RawPayload::Bytes {
                bytes: b"<Bytes>hello</Bytes>".to_vec(),
            },
            b"<Bytes>hello</Bytes>".to_vec(),
        ),
    ];
    for (payload, exact_bytes) in payloads {
        for unwatermarked in [false, true] {
            for legacy in [false, true] {
                let response = futures::executor::block_on(async {
                    if legacy {
                        let request = HostSignRawWithLegacyAccountRequest::V1(
                            v01::HostSignRawWithLegacyAccountRequest {
                                signer: subxt::utils::AccountId32(identity.public.to_bytes())
                                    .to_string(),
                                payload: payload.clone(),
                            },
                        );
                        let HostSignRawWithLegacyAccountResponse::V1(response) = if unwatermarked {
                            runtime
                                .sign_raw_deprecated_i_will_change_this_later_with_legacy_account(
                                    &cx, request,
                                )
                                .await
                        } else {
                            runtime.sign_raw_with_legacy_account(&cx, request).await
                        }
                        .unwrap();
                        response
                    } else {
                        let request = HostSignRawRequest::V1(v01::HostSignRawRequest {
                            account: product_account(0),
                            payload: payload.clone(),
                        });
                        let HostSignRawResponse::V1(response) = if unwatermarked {
                            runtime
                                .sign_raw_deprecated_i_will_change_this_later(&cx, request)
                                .await
                        } else {
                            runtime.sign_raw(&cx, request).await
                        }
                        .unwrap();
                        response
                    }
                });
                let expected = if unwatermarked || exact_bytes.starts_with(b"<Bytes>") {
                    exact_bytes.clone()
                } else {
                    [b"<Bytes>".as_slice(), &exact_bytes, b"</Bytes>"].concat()
                };
                let public = if legacy {
                    &identity.public
                } else {
                    &product.public
                };
                let signature = schnorrkel::Signature::from_bytes(&response.signature).unwrap();
                public
                    .verify_simple(b"substrate", &expected, &signature)
                    .unwrap();
                assert!(response.signed_transaction.is_none());
                if expected != exact_bytes {
                    assert!(
                        public
                            .verify_simple(b"substrate", &exact_bytes, &signature)
                            .is_err()
                    );
                } else {
                    let double_wrapped = [b"<Bytes>".as_slice(), &expected, b"</Bytes>"].concat();
                    assert!(
                        public
                            .verify_simple(b"substrate", &double_wrapped, &signature)
                            .is_err()
                    );
                }
            }
        }
    }
}

#[test]
fn unwatermarked_signing_keeps_authorization_and_confirmation_gates() {
    for legacy in [false, true] {
        for failure in [
            "no session",
            "wrong account",
            "permission",
            "declined",
            "confirmation error",
            "invalid hex",
        ] {
            let platform = Arc::new(StubPlatform {
                sign_raw_confirmed: failure != "declined",
                sign_raw_error: (failure == "confirmation error").then_some("failed"),
                remote_permission_denied: failure == "permission",
                ..Default::default()
            });
            let (services, activation) = signing_runtime_with_platform(platform);
            if failure != "no session" {
                futures::executor::block_on(activation.activate_local_session(ENTROPY.to_vec()))
                    .unwrap();
            }
            let runtime = product_runtime(services, activation);
            let cx = CallContext::default();
            let payload = if failure == "invalid hex" {
                v01::RawPayload::Payload {
                    payload: "0xzz".into(),
                }
            } else {
                v01::RawPayload::Bytes {
                    bytes: vec![0x11; 32],
                }
            };
            let rejected = futures::executor::block_on(async {
                if legacy {
                    let account = if failure == "wrong account" {
                        [0xff; 32]
                    } else {
                        derive_identity_keypair(&ENTROPY, TEST_NETWORK_SUFFIX)
                            .unwrap()
                            .public
                            .to_bytes()
                    };
                    runtime
                        .sign_raw_deprecated_i_will_change_this_later_with_legacy_account(
                            &cx,
                            HostSignRawWithLegacyAccountRequest::V1(
                                v01::HostSignRawWithLegacyAccountRequest {
                                    signer: subxt::utils::AccountId32(account).to_string(),
                                    payload,
                                },
                            ),
                        )
                        .await
                        .is_err()
                } else {
                    let mut account = product_account(0);
                    if failure == "wrong account" {
                        account.dot_ns_identifier = "other.dot".into();
                    }
                    runtime
                        .sign_raw_deprecated_i_will_change_this_later(
                            &cx,
                            HostSignRawRequest::V1(v01::HostSignRawRequest { account, payload }),
                        )
                        .await
                        .is_err()
                }
            });
            assert!(rejected, "{failure}, legacy={legacy}");
        }
    }
}

#[test]
fn paired_signing_host_signs_unwatermarked_proofs_only_after_confirmation() {
    for legacy in [false, true] {
        for confirmed in [false, true] {
            let platform = Arc::new(StubPlatform {
                sign_raw_confirmed: confirmed,
                ..Default::default()
            });
            let (_, activation) = signing_runtime_with_platform(platform);
            futures::executor::block_on(activation.activate_local_session(ENTROPY.to_vec()))
                .unwrap();
            let service = SigningHostSsoService::new(activation);
            let identity = derive_identity_keypair(&ENTROPY, TEST_NETWORK_SUFFIX).unwrap();
            let root = derive_root_keypair_from_entropy(&ENTROPY).unwrap();
            let product = derive_product_keypair(&root, "myapp.dot", index_bytes(0)).unwrap();
            let payload = v01::RawPayload::Bytes {
                bytes: vec![0x11; 32],
            };
            let request = if legacy {
                SignRequest::RawWithLegacyAccountUnwatermarkedDeprecated(
                    SignRawWithLegacyAccountRequest {
                        account: identity.public.to_bytes(),
                        data: payload,
                    },
                )
            } else {
                SignRequest::RawUnwatermarkedDeprecated(v01::HostSignRawRequest {
                    account: product_account(0),
                    payload,
                })
            };
            let encoded = request.encode();
            assert_eq!(encoded[0], if legacy { 3 } else { 2 });
            let request = SignRequest::decode(&mut encoded.as_slice()).unwrap();
            let Dispatch::Response(answer) = futures::executor::block_on(service.dispatch(
                service.current_session(),
                RemoteMessage {
                    message_id: "proof".into(),
                    data: RemoteMessageData::V1(v1::RemoteMessage::SignRequest(request)),
                },
            )) else {
                panic!("expected signing response")
            };
            let RemoteMessageData::V1(v1::RemoteMessage::SignResponse(response)) =
                answer.message.data
            else {
                panic!("expected SignResponse")
            };
            if confirmed {
                let response = response.payload.unwrap();
                let signature = schnorrkel::Signature::from_bytes(&response.signature).unwrap();
                let public = if legacy {
                    &identity.public
                } else {
                    &product.public
                };
                public
                    .verify_simple(b"substrate", &[0x11; 32], &signature)
                    .unwrap();
                assert!(
                    public
                        .verify_simple(
                            b"substrate",
                            &[b"<Bytes>".as_slice(), &[0x11; 32], b"</Bytes>"].concat(),
                            &signature
                        )
                        .is_err()
                );
            } else {
                assert_eq!(response.payload.unwrap_err(), "Rejected");
            }
        }
    }
}
