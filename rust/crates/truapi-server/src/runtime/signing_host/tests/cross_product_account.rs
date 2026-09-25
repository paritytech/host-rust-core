//! Signing with an account a publisher granted to another product.
//!
//! The staging name of a product asks for the product's own account, which is
//! what `trustedProducts` is for. These go through the signing role end to
//! end, so what they pin is the signature: whose key actually signed, not only
//! which door the request got through.

use super::*;

use crate::host_logic::statement_store::current_unix_secs;
use crate::runtime::product_manifest::{CachedManifest, manifest_cache_key};
use parity_scale_codec::Encode;
use truapi::api::StatementStore;
use truapi::versioned::signing::{
    HostCreateTransactionRequest, HostCreateTransactionResponse, HostSignPayloadError,
    HostSignPayloadRequest, HostSignPayloadResponse,
};
use truapi::versioned::statement_store::{
    RemoteStatementStoreCreateProofRequest, RemoteStatementStoreCreateProofResponse,
};
use truapi_platform::{CoreStorage, PermissionAuthorizationStatus};

/// Seed `owner`'s manifest cache, so the grant resolves without a chain.
fn cache_grant(platform: &StubPlatform, owner: &str, trusted: &str) {
    let entry = CachedManifest {
        fetched_at_secs: current_unix_secs(),
        json: Some(format!(r#"{{"$v":1,"trustedProducts":{trusted}}}"#)),
    };
    futures::executor::block_on(
        platform.write_core_storage(manifest_cache_key(owner), entry.encode()),
    )
    .expect("stub core storage accepts the entry");
}

fn dim2_account() -> v01::ProductAccountId {
    v01::ProductAccountId {
        dot_ns_identifier: "dim2.paseo".to_string(),
        derivation_index: v01::DerivationIndex::Index(0),
    }
}

/// `dim2next.paseo` signs a payload with `dim2.paseo`'s account.
fn sign_as_dim2next(
    platform: Arc<StubPlatform>,
) -> Result<v01::HostSignPayloadResponse, CallError<HostSignPayloadError>> {
    let (services, activation) = signing_runtime_with_platform(platform);
    futures::executor::block_on(activation.activate_local_session(ENTROPY.to_vec()))
        .expect("the local session activates");
    let runtime = product_runtime_for(services, activation, "dim2next.paseo");

    futures::executor::block_on(runtime.sign_payload(
        &CallContext::default(),
        HostSignPayloadRequest::V1(v01::HostSignPayloadRequest {
            account: dim2_account(),
            payload: crate::test_support::sign_payload_data(),
        }),
    ))
    .map(|HostSignPayloadResponse::V1(response)| response)
}

#[test]
fn a_context_grant_signs_with_the_granting_products_account() {
    let platform = Arc::new(StubPlatform {
        sign_payload_confirmed: true,
        ..Default::default()
    });
    cache_grant(&platform, "dim2.paseo", r#"{"dim2next":["context"]}"#);

    let response = sign_as_dim2next(platform).expect("the grant admits the account");

    // The account that signed is the one the grant was published for, not the
    // caller's own: a product acting for another does not sign as itself.
    let root = derive_root_keypair_from_entropy(&ENTROPY).expect("root derives");
    let owner =
        derive_product_keypair(&root, "dim2.paseo", index_bytes(0)).expect("owner key derives");
    let preimage = crate::host_logic::transaction::extrinsic_payload_preimage(
        &crate::test_support::sign_payload_data(),
    )
    .expect("preimage builds");
    let signature =
        schnorrkel::Signature::from_bytes(&response.signature[1..]).expect("64-byte signature");
    assert!(
        owner
            .public
            .verify_simple(b"substrate", &preimage, &signature)
            .is_ok(),
        "dim2.paseo's account signed the payload",
    );
}

#[test]
fn an_ungranted_product_cannot_sign_with_the_account() {
    let platform = Arc::new(StubPlatform {
        sign_payload_confirmed: true,
        ..Default::default()
    });
    cache_grant(&platform, "dim2.paseo", r#"{}"#);

    let error = sign_as_dim2next(platform).expect_err("no grant names this caller");

    assert!(
        matches!(
            error,
            CallError::Domain(HostSignPayloadError::V1(
                v01::HostSignPayloadError::PermissionDenied
            ))
        ),
        "expected PermissionDenied, got {error:?}",
    );
}

/// The user still sees what they are approving. A grant is the publisher's
/// answer about which product may act; it is not the user's answer about a
/// signature, which this role asks for every time.
#[test]
fn a_granted_signature_is_still_confirmed_by_the_user() {
    let platform = Arc::new(StubPlatform {
        sign_payload_confirmed: false,
        ..Default::default()
    });
    cache_grant(&platform, "dim2.paseo", r#"{"dim2next":["context"]}"#);

    sign_as_dim2next(platform.clone()).expect_err("a refused confirmation refuses the signature");

    assert_eq!(
        platform
            .sign_payload_reviews
            .lock()
            .expect("sign payload review list mutex poisoned")
            .len(),
        1,
        "the grant does not waive the per-signature confirmation",
    );
}

#[test]
fn blessed_jollity_signs_as_dim2_only_with_the_owners_grant() {
    use crate::host_logic::statement_store::{
        statement_fields_from_v01, unsigned_statement_signing_payload,
    };

    let root = derive_root_keypair_from_entropy(&ENTROPY).unwrap();
    for suffix in ["testnet", "paseo"] {
        let caller = format!("jollity.{suffix}");
        let owner = format!("dim2.{suffix}");
        let keypair = derive_product_keypair(&root, &owner, index_bytes(1)).unwrap();
        for granted in [false, true] {
            let platform = Arc::new(StubPlatform {
                permission_storage_error: Some("permission storage must not be read"),
                ..Default::default()
            });
            cache_grant(
                &platform,
                &owner,
                if granted {
                    r#"{"jollity":["context"]}"#
                } else {
                    "{}"
                },
            );
            for (requester, target) in [("jollity", "dim2"), (caller.as_str(), owner.as_str())] {
                futures::executor::block_on(
                    crate::host_logic::permissions::set_account_access_status(
                        platform.as_ref(),
                        requester,
                        target,
                        PermissionAuthorizationStatus::Denied,
                    ),
                )
                .unwrap();
            }
            let stored = platform.local_storage.lock().unwrap().clone();
            let (services, authority) = signing_runtime_with_platform(platform.clone());
            futures::executor::block_on(authority.activate_local_session(ENTROPY.to_vec()))
                .unwrap();
            let runtime = product_runtime_for(services, authority, &caller);
            let account = v01::ProductAccountId {
                dot_ns_identifier: owner.clone(),
                derivation_index: v01::DerivationIndex::Index(1),
            };
            let cx = CallContext::default();
            let verify = |signature: &[u8], payload: &[u8]| {
                keypair
                    .public
                    .verify_simple(
                        SR25519_SIGNING_CONTEXT,
                        payload,
                        &schnorrkel::Signature::from_bytes(signature).unwrap(),
                    )
                    .is_ok()
            };
            let payload = crate::test_support::sign_payload_data();
            let payload_preimage = extrinsic_payload_preimage(&payload).unwrap();
            let payload_signed = futures::executor::block_on(runtime.sign_payload(
                &cx,
                HostSignPayloadRequest::V1(v01::HostSignPayloadRequest {
                    account: account.clone(),
                    payload,
                }),
            ))
            .is_ok_and(|HostSignPayloadResponse::V1(response)| {
                verify(&response.signature[1..], &payload_preimage)
            });
            let raw_signed = futures::executor::block_on(runtime.sign_raw(
                &cx,
                HostSignRawRequest::V1(v01::HostSignRawRequest {
                    account: account.clone(),
                    payload: v01::RawPayload::Bytes {
                        bytes: b"hello".to_vec(),
                    },
                }),
            ))
            .is_ok_and(|HostSignRawResponse::V1(response)| {
                verify(&response.signature, b"<Bytes>hello</Bytes>")
            });
            let transaction_signed = futures::executor::block_on(runtime.create_transaction(
                &cx,
                HostCreateTransactionRequest::V1(v01::ProductAccountTxPayload {
                    signer: account.clone(),
                    ..tx_payload(0)
                }),
            ))
            .is_ok_and(|HostCreateTransactionResponse::V1(response)| {
                let (signer, signature, _) = split_v4(&response.transaction);
                signer == keypair.public.to_bytes() && verify(&signature, &[0, 0, 1, 2, 3])
            });
            let statement = crate::test_support::statement();
            let statement_payload = unsigned_statement_signing_payload(
                statement_fields_from_v01(statement.clone()).unwrap(),
            )
            .unwrap();
            let statement_signed = futures::executor::block_on(StatementStore::create_proof(
                &runtime,
                &cx,
                RemoteStatementStoreCreateProofRequest::V1(
                    v01::RemoteStatementStoreCreateProofRequest {
                        product_account_id: account,
                        statement,
                    },
                ),
            ))
            .is_ok_and(|RemoteStatementStoreCreateProofResponse::V1(response)| {
                match response.proof {
                    v01::StatementProof::Sr25519 { signer, signature } => {
                        signer == keypair.public.to_bytes()
                            && verify(&signature, &statement_payload)
                    }
                    _ => false,
                }
            });
            assert_eq!(
                (
                    [
                        payload_signed,
                        raw_signed,
                        transaction_signed,
                        statement_signed
                    ],
                    platform.remote_permission_requests.lock().unwrap().len(),
                    platform.sign_payload_reviews.lock().unwrap().len(),
                    platform.sign_raw_reviews.lock().unwrap().len(),
                    platform.create_transaction_reviews.lock().unwrap().len(),
                    platform
                        .statement_store_product_sign_reviews
                        .lock()
                        .unwrap()
                        .len(),
                    platform.local_storage.lock().unwrap().clone(),
                ),
                ([granted; 4], 0, 0, 0, 0, 0, stored),
                "{caller} signing as {owner}, grant: {granted}",
            );
        }
    }
}
