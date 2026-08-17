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

/// `LIVE_ASSET_HUB_WS` points the dotNS checks at another Asset Hub, for
/// instance previewnet's `wss://previewnet.substrate.dev/asset-hub`.
fn asset_hub_ws() -> String {
    std::env::var("LIVE_ASSET_HUB_WS").unwrap_or_else(|_| ASSET_HUB_WS.to_string())
}
const PEOPLE_WS: &str = "wss://paseo-people-next-system-rpc.polkadot.io";

/// The ring our onboarded test identity sits in.
const RING_INDEX: u32 = 2;

async fn asset_hub() -> (alloc::rpc::RpcClient, alloc::extension::Metadata) {
    let rpc = alloc::rpc::RpcClient::connect(&asset_hub_ws())
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

// ---------------------------------------------------------------------------
// dotNS gateway: the register_name authorization shape and the username reads.
// ---------------------------------------------------------------------------

use truapi_server::host_logic::dotns_gateway::{
    DotnsTransport, VIEW_CALL_ORIGIN, call_bytes32, classify_labels, decode_address,
    decode_revive_call_output, discover_pop_controller, encode_revive_call, label_available,
    namehash_under, resolve_labels, selector,
};
use truapi_server::statement_allowance::extension::AS_DOTNS_GATEWAY;

/// The `DotnsRegistrar` (ERC721), the same CREATE3 address on every network
/// per dotns `DEPLOYMENTS.md`. Only used to find an account that holds a
/// settled name.
const DOTNS_REGISTRAR: [u8; 20] = [
    0x4f, 0x06, 0xe8, 0x18, 0xba, 0x3d, 0x98, 0x77, 0x04, 0xfd, 0x91, 0xcf, 0x3d, 0x86, 0x8e, 0x4b,
    0x01, 0x91, 0x06, 0xab,
];

/// A label minted through the public registrar on the checked network, whose
/// owner therefore has a settled `LabelStore`. `LIVE_MINTED_LABEL` overrides
/// the paseo-next-v2 default (`e2epoolns01`); `LIVE_TLD` names the network TLD
/// (`paseo` by default, `dot` on previewnet).
fn minted_label() -> String {
    std::env::var("LIVE_MINTED_LABEL").unwrap_or_else(|_| "e2epoolns01".to_string())
}

/// `namehash(<minted label>.<tld>)`, the registrar's token id.
fn minted_node() -> [u8; 32] {
    let tld = std::env::var("LIVE_TLD").unwrap_or_else(|_| "paseo".to_string());
    namehash_under(&namehash_under(&[0u8; 32], &tld), &minted_label())
}

/// `DotnsTransport` over plain RPC, the same two primitives the CLI uses.
struct PlainRpc(alloc::rpc::RpcClient);

#[truapi_platform::async_trait]
impl DotnsTransport for PlainRpc {
    async fn storage(&mut self, key: Vec<u8>) -> Result<Option<Vec<u8>>, String> {
        self.0
            .get_storage(&key)
            .await
            .map_err(|err| err.to_string())
    }

    async fn view(&mut self, dest: &[u8; 20], input: Vec<u8>) -> Result<Vec<u8>, String> {
        let args = encode_revive_call(&VIEW_CALL_ORIGIN, dest, &input);
        let output = self
            .0
            .call(
                "state_call",
                serde_json::json!(["ReviveApi_call", format!("0x{}", hex::encode(args))]),
            )
            .await
            .map_err(|err| err.to_string())?;
        let output = output.as_str().ok_or("state_call output is not a string")?;
        let bytes = hex::decode(output.trim_start_matches("0x")).map_err(|err| err.to_string())?;
        decode_revive_call_output(&bytes).map_err(|err| err.to_string())
    }
}

/// `register_name` is authorized by `AsDotnsGatewayInfo::RegisterFullName`.
/// The host asserts its exact field shape before signing, and the encoded
/// extra has to match it field for field: a shorter payload is accepted
/// locally and rejected (or worse) by the runtime. The vendored fixture is a
/// snapshot; this is the live shape.
#[tokio::test]
#[ignore = "needs network access to a live Asset Hub"]
async fn live_asset_hub_declares_the_register_full_name_shape() {
    let (_rpc, metadata) = asset_hub().await;
    let variant = metadata
        .dotns_register_full_name_variant()
        .expect("RegisterFullName is {proof, ring_index, revision, signature}");
    assert_eq!(
        metadata
            .extension_info_field_count(AS_DOTNS_GATEWAY, "RegisterFullName")
            .unwrap(),
        4
    );
    metadata
        .call_indices("DotnsGateway", "register_name")
        .expect("DotnsGateway.register_name exists");
    println!("live AsDotnsGateway: RegisterFullName={variant}");
}

/// End to end over the same resolution steps the CLI and the in-core runtime
/// share: pallet storage → dispatcher `TARGET()` → controller → registry →
/// store factory → the owner's `LabelStore` → bare labels. The owner is found
/// through the registrar, so this covers the warm path (a settled store, whose
/// labels carry the network TLD) rather than only pending claims.
#[tokio::test]
#[ignore = "needs network access to a live Asset Hub"]
async fn live_asset_hub_resolves_a_settled_store_over_dotns_discovery() {
    let (rpc, _metadata) = asset_hub().await;
    let mut transport = PlainRpc(rpc);

    let controller = discover_pop_controller(&mut transport)
        .await
        .expect("discovery")
        .expect("the gateway is deployed with a dispatcher");
    println!("live DotnsPopController: 0x{}", hex::encode(controller));

    // ownerOf(namehash) on the ERC721 registrar. Eth-derived owners map back
    // to an AccountId32 by `0xEE` padding, which `account_to_h160` truncates.
    let owner_output = transport
        .view(
            &DOTNS_REGISTRAR,
            call_bytes32("ownerOf(uint256)", &minted_node()),
        )
        .await
        .expect("registrar ownerOf");
    let owner = decode_address(&owner_output).expect("owner address");
    let mut account = [0xEE; 32];
    account[..20].copy_from_slice(&owner);
    assert_eq!(hex::encode(selector("ownerOf(uint256)")), "6352211e");

    let labels = resolve_labels(&mut transport, &controller, &account)
        .await
        .expect("resolve labels");
    println!("live labels of 0x{}: {labels:?}", hex::encode(owner));
    assert!(
        labels.iter().any(|label| *label == minted_label()),
        "the settled store label loses its network TLD: {labels:?}"
    );
    assert!(
        labels.iter().all(|label| !label.contains('.')),
        "no TLD or subname survives: {labels:?}"
    );
    let identity = classify_labels(&labels);
    assert!(
        identity.lite_username.is_some() || identity.full_username.is_some(),
        "labels classify into a username"
    );
}

/// A reservation or registration for a name the registrar already minted can
/// never succeed, so the CLI asks the registrar first. `available` is read for
/// the name's node under the network TLD (`tldNode()`), the same node the
/// registrar minted.
#[tokio::test]
#[ignore = "needs network access to a live Asset Hub"]
async fn live_asset_hub_reports_registered_names_as_unavailable() {
    let (rpc, _metadata) = asset_hub().await;
    let mut transport = PlainRpc(rpc);
    let controller = discover_pop_controller(&mut transport)
        .await
        .expect("discovery")
        .expect("gateway deployed");

    assert!(
        !label_available(&mut transport, &controller, &minted_label())
            .await
            .expect("available view"),
        "a minted name is not available"
    );
    assert!(
        label_available(&mut transport, &controller, "truapihostrebasecheckzz")
            .await
            .expect("available view"),
        "an unminted name is available"
    );
}
