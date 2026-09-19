//! An AutoSigning grant waives the per-call confirmation on the signing role.

use super::*;

/// Allocate an AutoSigning grant for the runtime's own product.
fn grant_auto_signing(runtime: &ProductRuntimeHost) {
    let allocation = futures::executor::block_on(ResourceAllocation::request(
        runtime,
        &CallContext::default(),
        HostRequestResourceAllocationRequest::V1(v01::HostRequestResourceAllocationRequest {
            resources: vec![v01::AllocatableResource::AutoSigning],
        }),
    ))
    .expect("approved AutoSigning allocation succeeds");
    let HostRequestResourceAllocationResponse::V1(allocation) = allocation;
    assert_eq!(allocation.outcomes, vec![v01::AllocationOutcome::Allocated]);
}

/// A platform that approves the allocation and declines every signing prompt,
/// so any call that succeeds did so without asking.
fn granting_platform() -> Arc<StubPlatform> {
    Arc::new(StubPlatform {
        resource_allocation_confirmed: true,
        sign_raw_confirmed: false,
        sign_payload_confirmed: false,
        create_transaction_confirmed: false,
        ..StubPlatform::default()
    })
}

fn raw_request(product_id: &str) -> HostSignRawRequest {
    HostSignRawRequest::V1(v01::HostSignRawRequest {
        account: v01::ProductAccountId {
            dot_ns_identifier: product_id.to_string(),
            derivation_index: v01::DerivationIndex::Index(0),
        },
        payload: v01::RawPayload::Bytes {
            bytes: b"hello world".to_vec(),
        },
    })
}

#[test]
fn a_granted_product_signs_raw_without_a_prompt() {
    let platform = granting_platform();
    let (services, activation) = signing_runtime_with_platform(platform.clone());
    futures::executor::block_on(activation.activate_local_session(ENTROPY.to_vec()))
        .expect("activation succeeds");
    let runtime = product_runtime(services, activation);
    grant_auto_signing(&runtime);

    let HostSignRawResponse::V1(response) = futures::executor::block_on(
        runtime.sign_raw(&CallContext::default(), raw_request("myapp.dot")),
    )
    .expect("a granted product signs without confirmation");

    assert!(
        platform
            .sign_raw_reviews
            .lock()
            .expect("raw signing review list mutex poisoned")
            .is_empty(),
        "the grant waives the prompt",
    );
    let root = derive_root_keypair_from_entropy(&ENTROPY).unwrap();
    let keypair = derive_product_keypair(&root, "myapp.dot", index_bytes(0)).unwrap();
    let signature =
        schnorrkel::Signature::from_bytes(&response.signature).expect("64-byte signature");
    assert!(
        keypair
            .public
            .verify_simple(b"substrate", b"<Bytes>hello world</Bytes>", &signature)
            .is_ok(),
        "the grant signs the same bytes the prompt would have shown",
    );
}

#[test]
fn an_ungranted_product_still_prompts_for_raw_signing() {
    let platform = granting_platform();
    let (services, activation) = signing_runtime_with_platform(platform.clone());
    futures::executor::block_on(activation.activate_local_session(ENTROPY.to_vec()))
        .expect("activation succeeds");
    let runtime = product_runtime(services, activation);

    let error = futures::executor::block_on(
        runtime.sign_raw(&CallContext::default(), raw_request("myapp.dot")),
    )
    .expect_err("the stub declines the confirmation");

    assert!(matches!(
        error,
        CallError::Domain(HostSignRawError::V1(v01::HostSignPayloadError::Rejected))
    ));
    assert_eq!(
        platform
            .sign_raw_reviews
            .lock()
            .expect("raw signing review list mutex poisoned")
            .len(),
        1,
        "without a grant the user is asked exactly once",
    );
}

#[test]
fn a_grant_does_not_cover_the_unwatermarked_raw_signing_api() {
    // The deprecated API's signatures are not domain-separated from
    // transaction signatures, so a standing grant must not waive its prompt.
    let platform = granting_platform();
    let (services, activation) = signing_runtime_with_platform(platform.clone());
    futures::executor::block_on(activation.activate_local_session(ENTROPY.to_vec()))
        .expect("activation succeeds");
    let runtime = product_runtime(services, activation);
    grant_auto_signing(&runtime);

    #[allow(deprecated)]
    let error = futures::executor::block_on(
        runtime
            .sign_raw_unwatermarked_deprecated(&CallContext::default(), raw_request("myapp.dot")),
    )
    .expect_err("the stub declines the confirmation");

    assert!(matches!(
        error,
        CallError::Domain(HostSignRawError::V1(v01::HostSignPayloadError::Rejected))
    ));
    assert_eq!(
        platform
            .sign_raw_reviews
            .lock()
            .expect("raw signing review list mutex poisoned")
            .len(),
        1,
        "the unwatermarked API prompts whatever the grant says",
    );
}
