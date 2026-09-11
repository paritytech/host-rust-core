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
fn unwatermarked_signing_signs_the_supplied_bytes() {
    let (services, activation) = signing_runtime();
    futures::executor::block_on(activation.activate_local_session(ENTROPY.to_vec())).unwrap();
    let identity = derive_identity_keypair(&ENTROPY, TEST_NETWORK_SUFFIX).unwrap();
    let root = derive_root_keypair_from_entropy(&ENTROPY).unwrap();
    let product = derive_product_keypair(&root, "myapp.dot", index_bytes(0)).unwrap();
    let runtime = product_runtime(services, activation);
    let cx = CallContext::default();
    for legacy in [false, true] {
        let payload = v01::RawPayload::Bytes {
            bytes: vec![0x11; 32],
        };
        let response = futures::executor::block_on(async {
            if legacy {
                let HostSignRawWithLegacyAccountResponse::V1(response) = runtime
                    .sign_raw_unwatermarked_deprecated_with_legacy_account(
                        &cx,
                        HostSignRawWithLegacyAccountRequest::V1(
                            v01::HostSignRawWithLegacyAccountRequest {
                                signer: subxt::utils::AccountId32(identity.public.to_bytes())
                                    .to_string(),
                                payload,
                            },
                        ),
                    )
                    .await
                    .unwrap();
                response
            } else {
                let HostSignRawResponse::V1(response) = runtime
                    .sign_raw_unwatermarked_deprecated(
                        &cx,
                        HostSignRawRequest::V1(v01::HostSignRawRequest {
                            account: product_account(0),
                            payload,
                        }),
                    )
                    .await
                    .unwrap();
                response
            }
        });
        let public = if legacy {
            &identity.public
        } else {
            &product.public
        };
        let signature = schnorrkel::Signature::from_bytes(&response.signature).unwrap();
        public
            .verify_simple(b"substrate", &[0x11; 32], &signature)
            .unwrap();
        assert!(
            public
                .verify_simple(
                    b"substrate",
                    &[b"<Bytes>".as_slice(), &[0x11; 32], b"</Bytes>"].concat(),
                    &signature,
                )
                .is_err()
        );
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
