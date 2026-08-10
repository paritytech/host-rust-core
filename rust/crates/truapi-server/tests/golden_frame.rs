//! Binary golden-frame regression test.
//!
//! `tests/snapshots/golden-account-get.bin` holds the raw bytes of an
//! `account_get_account_request` frame. The tests assert both halves of the
//! envelope: the transport framing (`requestId` and the `(trait, method)`
//! discriminant pair) and the *typed decode of the payload*.
//!
//! Both halves are needed. The payload is inlined as opaque bytes, so a
//! `ProtocolMessage`-only assertion is satisfied by a payload of any length,
//! and round-tripping the in-memory shape cancels a symmetric layout change
//! out. Only decoding the payload into its current type reads what the bytes
//! actually say.
//!
//! The frame encodes:
//!   requestId = "p:1"
//!   payload   = account_get_account_request,
//!               inner = HostAccountGetRequest::V1(ProductAccountId {
//!                   dot_ns_identifier: "foo",
//!                   derivation_index: DerivationIndex::Index(0),
//!               })
//!
//! On the wire (16 bytes):
//!   [0c 70 3a 31]                      requestId = compact-len(3) + "p:1"
//!   [c1]                               trait discriminant 193 = account
//!   [04]                               method discriminant 4 = get_account request
//!   [00]                               versioned wrapper variant V1
//!   [0c 66 6f 6f]                      compact-len(3) + "foo"
//!   [00]                               DerivationIndex variant Index
//!   [00 00 00 00]                      u32 = 0
//!
//! If this test fails after a wire-protocol change, regenerate the file
//! deliberately, re-check the change against the wire table, and treat a
//! payload layout change as breaking for every product built against an
//! older `@parity/truapi`.

use parity_scale_codec::{Decode, Encode};
use truapi::v01;
use truapi::versioned::account::HostAccountGetRequest;
use truapi_server::frame::{Payload, ProtocolMessage};
use truapi_server::generated::wire_table;

const GOLDEN: &[u8] = include_bytes!("snapshots/golden-account-get.bin");

/// Payload byte count of the golden frame: one versioned-wrapper variant byte,
/// a compact-length-prefixed 3-byte identifier, one `DerivationIndex` variant
/// byte, and a `u32`. Spelled out term by term rather than measured from the
/// codec, so a layout change has to move this number by hand.
const GOLDEN_PAYLOAD_LEN: usize = 1 + 1 + 3 + 1 + 4;

fn expected_request() -> HostAccountGetRequest {
    HostAccountGetRequest::V1(v01::HostAccountGetRequest {
        product_account_id: v01::ProductAccountId {
            dot_ns_identifier: "foo".to_string(),
            derivation_index: v01::DerivationIndex::Index(0),
        },
    })
}

#[test]
fn golden_account_get_frame_decodes_to_expected_message() {
    let decoded = ProtocolMessage::decode(&mut &GOLDEN[..])
        .expect("golden frame must decode with the current wire codec");

    let expected = ProtocolMessage {
        request_id: "p:1".to_string(),
        payload: Payload {
            trait_id: wire_table::ACCOUNT_GET_ACCOUNT.trait_id,
            method_id: wire_table::ACCOUNT_GET_ACCOUNT.request_id,
            value: expected_request().encode(),
        },
    };
    assert_eq!(decoded, expected);
}

#[test]
fn golden_account_get_payload_decodes_as_the_typed_request() {
    let decoded = ProtocolMessage::decode(&mut &GOLDEN[..]).expect("decode");
    assert_eq!(
        decoded.payload.value.len(),
        GOLDEN_PAYLOAD_LEN,
        "account_get_account request payload changed length; every product \
         built against an older @parity/truapi now fails to decode"
    );

    let request = HostAccountGetRequest::decode(&mut &decoded.payload.value[..])
        .expect("golden payload must decode as the typed request");
    assert_eq!(request, expected_request());
}

#[test]
fn golden_account_get_frame_round_trips() {
    // Encoding the in-memory shape must reproduce the on-disk bytes exactly.
    let decoded = ProtocolMessage::decode(&mut &GOLDEN[..]).expect("decode");
    assert_eq!(decoded.encode(), GOLDEN);
}
