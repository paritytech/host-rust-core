//! Live Asset Hub checks for the PGAS claim path.
//!
//! Ignored by default; these need network access to paseo-next-v2's Asset Hub.
//!
//! ```sh
//! cargo +nightly test -p truapi-host-cli --test live_asset_hub -- --ignored --nocapture
//! ```
//!
//! Connects directly rather than through the host's `ChainProvider`, so the checks
//! are about the chain rather than about host wiring. The provider routes Asset Hub
//! now that the preset serves it as a role.

use truapi_server::statement_allowance::{self as alloc, extension::AS_PGAS, pgas};

const ASSET_HUB_WS: &str = "wss://paseo-asset-hub-next-rpc.polkadot.io";
const PEOPLE_WS: &str = "wss://paseo-people-next-system-rpc.polkadot.io";

/// The ring our onboarded test identity sits in.
const RING_INDEX: u32 = 2;

async fn asset_hub() -> (alloc::rpc::RpcClient, alloc::extension::Metadata) {
    let rpc = alloc::rpc::RpcClient::connect(ASSET_HUB_WS)
        .await
        .expect("connect to Asset Hub");
    let metadata = alloc::fetch_metadata(&rpc)
        .await
        .expect("Asset Hub metadata");
    (rpc, metadata)
}

/// The claim encodes five fields for `AsPgas::Claim`. A short payload is accepted
/// locally and then panics the runtime inside `validate_transaction`, which is how
/// the missing `revision` on the statement-store claim went unnoticed.
#[tokio::test]
#[ignore = "needs network access to a live Asset Hub"]
async fn live_asset_hub_declares_the_pgas_claim_shape() {
    let (_rpc, metadata) = asset_hub().await;

    assert_eq!(
        metadata.metadata_version(),
        16,
        "the runtime API should serve V16"
    );
    assert_eq!(
        metadata
            .extension_info_field_count(AS_PGAS, "Claim")
            .unwrap(),
        5,
        "AsPgas::Claim arity changed; the encoded payload has to change with it"
    );
    let (claim, lite_people) = metadata
        .extension_info_and_field_variant_indices(AS_PGAS, "Claim", "LitePeople")
        .expect("AsPgas carries a LitePeople claim");
    println!("live AsPgas: Claim={claim} LitePeople={lite_people}");

    assert!(
        alloc::slot::max_pgas_claims(&metadata).unwrap() > 0,
        "a lite person must be allowed at least one claim per day"
    );
}

/// Asset Hub learns People's rings through `MembersSubscriber`. A claim can only
/// be authorized against a revision it has imported, so decode that storage for
/// real: the record projection is the part no offline fixture covers.
#[tokio::test]
#[ignore = "needs network access to a live Asset Hub and People chain"]
async fn live_asset_hub_has_imported_the_current_people_ring_revision() {
    let (asset_hub_rpc, asset_hub_metadata) = asset_hub().await;
    let people_rpc = alloc::rpc::RpcClient::connect(PEOPLE_WS)
        .await
        .expect("connect to the People chain");
    let people_metadata = alloc::fetch_metadata(&people_rpc)
        .await
        .expect("People metadata");
    let at = people_rpc.finalized_head().await.expect("finalized head");
    let revision = alloc::ring::read_ring_revision(&people_rpc, &people_metadata, RING_INDEX, &at)
        .await
        .expect("People reports a ring revision");
    println!("People ring {RING_INDEX} is at revision {revision}");

    pgas::await_ring_revision(&asset_hub_rpc, &asset_hub_metadata, RING_INDEX, revision)
        .await
        .expect("Asset Hub has imported the current revision");
}

/// A revision Asset Hub has moved past can never be verified, and has to be told
/// apart from one that simply has not arrived: the first means rebuild the proof,
/// the second means wait.
#[tokio::test]
#[ignore = "needs network access to a live Asset Hub"]
async fn live_asset_hub_reports_a_pruned_revision_rather_than_waiting() {
    let (rpc, metadata) = asset_hub().await;

    let err = pgas::await_ring_revision(&rpc, &metadata, RING_INDEX, 1)
        .await
        .expect_err("revision 1 is long pruned");

    assert!(
        err.to_string().contains("pruned"),
        "a pruned revision should not be waited out: {err}"
    );
}

/// The already-funded check reads a real asset account. The test identity claimed
/// PGAS earlier, so it must read as funded, and an account that never claimed must
/// not — a check that answered the same either way would silently disable itself.
#[tokio::test]
#[ignore = "needs network access to a live Asset Hub"]
async fn live_asset_hub_reports_whether_an_account_holds_a_full_claim() {
    let (rpc, metadata) = asset_hub().await;

    let claim_amount = metadata.constant_u128("Pgas", "PgasClaimAmount").unwrap();
    let asset_id = metadata.constant_u32("Pgas", "PgasAssetId").unwrap();
    println!("PGAS asset {asset_id}, claim amount {claim_amount}");

    // The onboarded test identity's own account, credited by earlier claims.
    let funded: [u8; 32] =
        hex::decode("ba7ec9e74688af5ae483a3f2c9421443f02a688b2928a1e6f43cc06692c5293c")
            .unwrap()
            .try_into()
            .unwrap();
    assert!(
        pgas::holds_a_full_claim(&rpc, &metadata, &funded)
            .await
            .expect("balance read"),
        "the test identity has claimed PGAS, so it should read as funded"
    );

    assert!(
        !pgas::holds_a_full_claim(&rpc, &metadata, &[0xcd; 32])
            .await
            .expect("balance read"),
        "an account that never claimed holds nothing"
    );
}

/// A revision the window skipped is as unreachable as one that fell off the front,
/// and has to report as pruned rather than waiting out the timeout.
///
/// paseo Asset Hub holds `[105, 106, 108]` for lite-people ring 5 — every other
/// ring is contiguous — so revision 107 is the live case that distinguishes
/// testing the newest held root from testing the oldest.
#[tokio::test]
#[ignore = "needs network access to a live Asset Hub"]
async fn live_asset_hub_reports_a_skipped_revision_as_pruned() {
    let (rpc, metadata) = asset_hub().await;

    let err = pgas::await_ring_revision(&rpc, &metadata, 5, 107)
        .await
        .expect_err("revision 107 was skipped for ring 5");

    assert!(
        err.to_string().contains("pruned"),
        "a skipped revision should not be waited out: {err}"
    );
}
