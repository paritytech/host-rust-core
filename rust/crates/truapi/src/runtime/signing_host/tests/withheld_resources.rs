//! A withheld resource is refused while the rest of the request is granted.

use super::*;

/// A platform that approves the allocation, so a refusal below is the
/// withholding rather than a declined confirmation.
fn granting_platform() -> Arc<StubPlatform> {
    Arc::new(StubPlatform {
        resource_allocation_confirmed: true,
        ..StubPlatform::default()
    })
}

/// Ask for `resources` and return the per-resource outcomes.
fn allocate(
    runtime: &ProductRuntimeHost,
    resources: Vec<v01::AllocatableResource>,
) -> Vec<v01::AllocationOutcome> {
    let response = futures::executor::block_on(ResourceAllocation::request(
        runtime,
        &CallContext::default(),
        HostRequestResourceAllocationRequest::V1(v01::HostRequestResourceAllocationRequest {
            resources,
        }),
    ))
    .expect("an approved allocation request is answered");
    let HostRequestResourceAllocationResponse::V1(response) = response;
    response.outcomes
}

#[test]
fn a_withheld_resource_is_refused_while_the_others_are_granted() {
    let (services, activation) = signing_runtime_with_platform(granting_platform());
    futures::executor::block_on(activation.activate_local_session(ENTROPY.to_vec()))
        .expect("activation succeeds");
    activation.set_grant_allowances_unchecked(true);
    activation.set_withheld_resources(vec!["AutoSigning".to_string()]);
    let runtime = product_runtime(services, activation);

    // The order is the request's, so a suite reads each resource's own answer
    // rather than one verdict for the batch.
    assert_eq!(
        allocate(
            &runtime,
            vec![
                v01::AllocatableResource::AutoSigning,
                v01::AllocatableResource::StatementStoreAllowance,
            ],
        ),
        vec![
            v01::AllocationOutcome::Rejected,
            v01::AllocationOutcome::Allocated,
        ],
    );
}

#[test]
fn withholding_nothing_leaves_every_resource_granted() {
    let (services, activation) = signing_runtime_with_platform(granting_platform());
    futures::executor::block_on(activation.activate_local_session(ENTROPY.to_vec()))
        .expect("activation succeeds");
    activation.set_grant_allowances_unchecked(true);
    let runtime = product_runtime(services, activation);

    assert_eq!(
        allocate(&runtime, vec![v01::AllocatableResource::AutoSigning]),
        vec![v01::AllocationOutcome::Allocated],
    );
}

#[test]
fn a_later_set_replaces_the_earlier_one() {
    let (services, activation) = signing_runtime_with_platform(granting_platform());
    futures::executor::block_on(activation.activate_local_session(ENTROPY.to_vec()))
        .expect("activation succeeds");
    activation.set_grant_allowances_unchecked(true);
    activation.set_withheld_resources(vec!["AutoSigning".to_string()]);
    activation.set_withheld_resources(vec!["BulletinAllowance".to_string()]);
    let runtime = product_runtime(services, activation);

    // Replacing rather than accumulating: a suite that narrows what it withholds
    // would otherwise keep refusing whatever it named first.
    assert_eq!(
        allocate(
            &runtime,
            vec![
                v01::AllocatableResource::AutoSigning,
                v01::AllocatableResource::BulletinAllowance,
            ],
        ),
        vec![
            v01::AllocationOutcome::Allocated,
            v01::AllocationOutcome::Rejected,
        ],
    );
}
