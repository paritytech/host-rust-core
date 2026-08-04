//! An offline chain for the coinage runtime's tests.
//!
//! [`crate::runtime::statement_allowance::rpc::testing::ScriptedRpc`] answers
//! requests in a fixed order, which is enough for a single read but not for a
//! whole operation: an extrinsic this layer assembles carries a fresh sr25519
//! signature, so a test cannot know its bytes in advance and cannot pre-script the
//! block that contains it.
//!
//! [`FakeChain`] answers by *method* instead. It remembers what was submitted,
//! serves it back inside the block it reports, and keys storage reads off the key
//! it was asked for — so a test describes the chain's state rather than the exact
//! sequence of round trips, and stays readable when a code change reorders reads.
//!
//! The double is deliberately thin. It does not execute anything: what an
//! extrinsic *does* is expressed by the storage and events the test hands it,
//! which keeps a passing test from passing because the fake agreed with the code
//! about something neither should know.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use parity_scale_codec::{Compact, Encode};
use scale_info::{PortableRegistry, TypeDef, TypeDefPrimitive};
use serde_json::json;
use sp_crypto_hashing::twox_128;
use subxt::ext::scale_encode::{EncodeAsFields, Field};
use subxt::ext::scale_value::{Primitive, Value as ScaleValue};
use subxt::metadata::ArcMetadata;
use subxt_rpcs::RpcClient as HostRpcClient;
use subxt_rpcs::client::{RawRpcFuture, RawRpcSubscription, RawValue, RpcClientT};

use crate::host_logic::coinage::types::{DenominationExponent, RingLocation};
use crate::runtime::coinage::storage;
use crate::runtime::statement_allowance::rpc::RpcClient;

/// Runtime metadata fixture every coinage test builds against.
pub const FIXTURE: &[u8] = include_bytes!("../../../tests/fixtures/paseo-next-v2-metadata.scale");

/// Block hash the fake reports as finalized.
pub const FINALIZED: &str = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

/// Height of that block.
pub const FINALIZED_NUMBER: u64 = 100;

/// Genesis hash the fake reports.
const GENESIS: &str = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

/// The same fixture through Subxt, which exposes the event variants the thin
/// metadata does not, so a test can synthesize a block's events.
pub fn subxt_metadata() -> ArcMetadata {
    ArcMetadata::from(subxt::Metadata::decode_from(FIXTURE).expect("the fixture decodes for subxt"))
}

/// `System.Events` holding one `System` event attributed to extrinsic `index`,
/// encoded exactly as the runtime stores it.
pub fn system_events(event_name: &str, index: u32) -> Vec<u8> {
    let metadata = subxt_metadata();
    let system = metadata.pallet_by_name("System").expect("System exists");
    let event = system
        .event_variants()
        .expect("System has events")
        .iter()
        .find(|event| event.name == event_name)
        .expect("the event exists");
    let values = ScaleValue::unnamed_composite(
        event
            .fields
            .iter()
            .map(|field| default_value(metadata.types(), field.ty.id)),
    );
    let mut fields = event
        .fields
        .iter()
        .map(|field| Field::new(field.ty.id, field.name.as_deref()));

    let mut bytes = Vec::new();
    Compact(1u32).encode_to(&mut bytes);
    // Phase::ApplyExtrinsic(index).
    0u8.encode_to(&mut bytes);
    index.encode_to(&mut bytes);
    system.event_index().encode_to(&mut bytes);
    event.index.encode_to(&mut bytes);
    values
        .encode_as_fields_to(&mut fields, metadata.types(), &mut bytes)
        .expect("the event payload encodes");
    Vec::<[u8; 32]>::new().encode_to(&mut bytes);
    bytes
}

/// A value of `type_id` with every field at its first/default variant.
pub fn default_value(types: &PortableRegistry, type_id: u32) -> ScaleValue {
    let ty = types.resolve(type_id).expect("metadata type exists");
    match &ty.type_def {
        TypeDef::Composite(composite) => ScaleValue::unnamed_composite(
            composite
                .fields
                .iter()
                .map(|field| default_value(types, field.ty.id)),
        ),
        TypeDef::Variant(variants) => {
            let variant = variants.variants.first().expect("variant exists");
            ScaleValue::unnamed_variant(
                variant.name.clone(),
                variant
                    .fields
                    .iter()
                    .map(|field| default_value(types, field.ty.id)),
            )
        }
        TypeDef::Sequence(_) => ScaleValue::unnamed_composite([]),
        TypeDef::Array(array) => ScaleValue::unnamed_composite(
            (0..array.len).map(|_| default_value(types, array.type_param.id)),
        ),
        TypeDef::Tuple(tuple) => ScaleValue::unnamed_composite(
            tuple
                .fields
                .iter()
                .map(|field| default_value(types, field.id)),
        ),
        TypeDef::Primitive(TypeDefPrimitive::Bool) => ScaleValue::bool(false),
        TypeDef::Primitive(TypeDefPrimitive::Str) => ScaleValue::string(String::new()),
        TypeDef::Primitive(_) | TypeDef::Compact(_) => {
            ScaleValue::unnamed_variant("", []).map_context(|_| 0);
            ScaleValue {
                value: subxt::ext::scale_value::ValueDef::Primitive(Primitive::U128(0)),
                context: (),
            }
        }
        TypeDef::BitSequence(_) => ScaleValue::unnamed_composite([]),
    }
}

/// `System::Events` key, an unhashed plain entry.
fn system_events_key() -> String {
    hex::encode(
        [
            twox_128(b"System").as_slice(),
            twox_128(b"Events").as_slice(),
        ]
        .concat(),
    )
}

/// How the fake reports the inclusion of what it was handed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Inclusion {
    /// Reported in a finalized block, dispatch successful.
    FinalizedSuccess,
    /// Reported in a finalized block, dispatch failed.
    FinalizedFailure,
    /// Reported in a non-finalized block. The caller must resolve it against
    /// finalized state.
    InBlock,
    /// Refused before inclusion, so nothing happened.
    Rejected,
}

/// A chain that answers by method rather than by call order.
#[derive(Clone)]
pub struct FakeChain(Arc<Inner>);

struct Inner {
    /// Storage by key hex, without the `0x`. An absent key reads as `None`.
    storage: Mutex<HashMap<String, Vec<u8>>>,
    /// Extrinsics handed to `author_submitAndWatchExtrinsic`, in order.
    submitted: Mutex<Vec<Vec<u8>>>,
    /// Every `(method, params)` seen.
    calls: Mutex<Vec<(String, String)>>,
    inclusion: Mutex<Inclusion>,
    fee: Mutex<u128>,
}

impl Default for FakeChain {
    fn default() -> Self {
        Self::new(Inclusion::FinalizedSuccess)
    }
}

impl FakeChain {
    /// A chain that reports every submission as `inclusion`.
    pub fn new(inclusion: Inclusion) -> Self {
        Self(Arc::new(Inner {
            storage: Mutex::new(HashMap::new()),
            submitted: Mutex::new(Vec::new()),
            calls: Mutex::new(Vec::new()),
            inclusion: Mutex::new(inclusion),
            fee: Mutex::new(0),
        }))
    }

    /// An [`RpcClient`] backed by this chain.
    pub fn rpc(&self) -> RpcClient {
        RpcClient::new(HostRpcClient::new(self.clone()))
    }

    /// Put a value at `key`.
    pub fn set_storage(&self, key: &[u8], value: Vec<u8>) {
        self.0
            .storage
            .lock()
            .unwrap()
            .insert(hex::encode(key), value);
    }

    /// Remove whatever is at `key`, so reads report absence.
    pub fn clear_storage(&self, key: &[u8]) {
        self.0.storage.lock().unwrap().remove(&hex::encode(key));
    }

    /// What the runtime should charge for an extrinsic.
    pub fn set_fee(&self, fee: u128) {
        *self.0.fee.lock().unwrap() = fee;
    }

    /// Change how later submissions are reported.
    pub fn set_inclusion(&self, inclusion: Inclusion) {
        *self.0.inclusion.lock().unwrap() = inclusion;
    }

    /// Extrinsics submitted so far.
    pub fn submitted(&self) -> Vec<Vec<u8>> {
        self.0.submitted.lock().unwrap().clone()
    }

    /// How many extrinsics have been submitted.
    pub fn submission_count(&self) -> usize {
        self.0.submitted.lock().unwrap().len()
    }

    /// Every `(method, params)` the fake was asked for.
    pub fn calls(&self) -> Vec<(String, String)> {
        self.0.calls.lock().unwrap().clone()
    }

    /// Whether any request named `method`.
    pub fn called(&self, method: &str) -> bool {
        self.0
            .calls
            .lock()
            .unwrap()
            .iter()
            .any(|(seen, _)| seen == method)
    }

    fn record(&self, method: &str, params: Option<&RawValue>) {
        self.0.calls.lock().unwrap().push((
            method.to_string(),
            params.map_or_else(|| "[]".to_string(), |params| params.get().to_string()),
        ));
    }

    /// The JSON reply for a plain request.
    fn reply(&self, method: &str, params: &serde_json::Value) -> serde_json::Value {
        match method {
            "chain_getBlockHash" => json!(GENESIS),
            "chain_getFinalizedHead" => json!(FINALIZED),
            "state_getRuntimeVersion" => json!({
                "specVersion": 1_000_000,
                "transactionVersion": 1,
            }),
            "chain_getHeader" => json!({ "number": format!("0x{FINALIZED_NUMBER:x}") }),
            // Every account is fresh, which is what a throwaway top-up holder is.
            "system_accountNextIndex" => json!(0),
            "state_getMetadata" => json!(format!("0x{}", hex::encode(FIXTURE))),
            // The block carries exactly the extrinsic just submitted, so its
            // index inside the block is always zero.
            "chain_getBlock" => {
                let submitted = self.0.submitted.lock().unwrap();
                let extrinsics: Vec<String> = submitted
                    .last()
                    .map(|extrinsic| format!("0x{}", hex::encode(extrinsic)))
                    .into_iter()
                    .collect();
                json!({ "block": { "extrinsics": extrinsics } })
            }
            "state_getStorage" => {
                let key = params
                    .get(0)
                    .and_then(serde_json::Value::as_str)
                    .map(|key| key.trim_start_matches("0x").to_string())
                    .unwrap_or_default();
                match self.0.storage.lock().unwrap().get(&key) {
                    Some(value) => json!(format!("0x{}", hex::encode(value))),
                    None => serde_json::Value::Null,
                }
            }
            // The bulk read a recovery scan uses: one round trip, many keys.
            "state_queryStorageAt" => {
                let storage = self.0.storage.lock().unwrap();
                let changes: Vec<serde_json::Value> = params
                    .get(0)
                    .and_then(serde_json::Value::as_array)
                    .into_iter()
                    .flatten()
                    .filter_map(|key| {
                        let key = key.as_str()?;
                        let value = storage.get(key.trim_start_matches("0x"))?;
                        Some(json!([key, format!("0x{}", hex::encode(value))]))
                    })
                    .collect();
                json!([{ "block": FINALIZED, "changes": changes }])
            }
            "state_call" => self.runtime_api(params),
            other => panic!("the fake chain was asked for an unmodelled method `{other}`"),
        }
    }

    /// The reply for a runtime-API call.
    fn runtime_api(&self, params: &serde_json::Value) -> serde_json::Value {
        let api = params
            .get(0)
            .and_then(serde_json::Value::as_str)
            .unwrap_or_default();
        match api {
            "TaggedTransactionQueue_validate_transaction" => {
                if *self.0.inclusion.lock().unwrap() == Inclusion::Rejected {
                    // `Err(Invalid::Payment)`: refused, nothing broadcast.
                    json!("0x0100 01".replace(' ', ""))
                } else {
                    // `Ok(ValidTransaction::default())`.
                    json!("0x00000000000000000000")
                }
            }
            "TransactionPaymentApi_query_info" => {
                let mut encoded = Compact(1_000_000u64).encode();
                encoded.extend(Compact(4_096u64).encode());
                encoded.push(0u8);
                encoded.extend(self.0.fee.lock().unwrap().encode());
                json!(format!("0x{}", hex::encode(encoded)))
            }
            other => panic!("the fake chain was asked for an unmodelled runtime API `{other}`"),
        }
    }
}

impl FakeChain {
    /// Put one recycler entry in a ring, as every read of it will report.
    ///
    /// Five storage reads answer for an entry (§6.1), and a fixture that sets only
    /// some of them makes the entry look onboarding rather than included — which
    /// tests would then read as "not ready yet" instead of "your fixture is
    /// incomplete".
    pub fn place_entry_in_ring(
        &self,
        exponent: DenominationExponent,
        member_key: [u8; 32],
        alias: [u8; 32],
        ring: RingLocation,
        members: &[[u8; 32]],
        immutable_since: Option<u64>,
    ) {
        let collection = storage::recycler_collection_id(exponent);

        // 1. The pallet's own record: which denomination collection it belongs to.
        self.set_storage(
            &storage::recyclers_coin_to_recycler_key(&member_key),
            exponent.get().encode(),
        );
        // 2. Where the Members pallet placed it.
        self.set_storage(
            &storage::members_key(&collection, &member_key),
            storage::RingPosition::Included {
                ring_index: ring.index.0,
                ring_page: 0,
                ring_position: 0,
            }
            .encode(),
        );
        // 3. The ring's fill and immutability.
        self.set_storage(
            &storage::ring_keys_status_key(&collection, ring.index),
            ring_status(members.len() as u32, immutable_since),
        );
        // 4. Its members and size, for proving.
        self.set_storage(&storage::collections_key(&collection), collection_info(9));
        self.set_storage(
            &storage::ring_keys_key(&collection, ring.index, 0),
            ring_page(members),
        );
        // 5. The root, whose revision a proof is built against.
        self.set_storage(
            &storage::ring_root_key(&collection, ring.index),
            ring_root(ring.revision.0),
        );
        // And the alias's own state, which is absent unless the chain locked it.
        self.clear_storage(&storage::recycler_alias_state_key(
            exponent, ring.index, &alias,
        ));
    }
}

/// `CollectionInfo { owner, mode, ring_size, self_inclusion_delay }`.
pub fn collection_info(ring_size: u8) -> Vec<u8> {
    let mut encoded = vec![1u8];
    encoded.extend([9u8; 32]);
    encoded.push(0u8);
    encoded.push(ring_size);
    encoded.push(0u8);
    encoded
}

/// One `RingKeys` page.
pub fn ring_page(members: &[[u8; 32]]) -> Vec<u8> {
    let mut encoded = Compact(members.len() as u32).encode();
    for member in members {
        encoded.extend_from_slice(member);
    }
    encoded
}

/// `RingStatus { total, included, immutable_since }`, everything included.
pub fn ring_status(count: u32, immutable_since: Option<u64>) -> Vec<u8> {
    let mut encoded = count.to_le_bytes().to_vec();
    encoded.extend(count.to_le_bytes());
    encoded.extend(immutable_since.encode());
    encoded
}

/// `RingRoot`, carrying the revision a proof will be built against.
pub fn ring_root(revision: u32) -> Vec<u8> {
    use subxt::ext::scale_encode::EncodeAsType;
    use subxt::ext::scale_value::{Composite, ValueDef};

    let thin = crate::runtime::statement_allowance::extension::Metadata::decode(FIXTURE)
        .expect("the fixture decodes");
    let type_id = thin
        .storage_value_type("Members", "Root")
        .expect("Members.Root is in metadata");
    let subxt = subxt_metadata();
    let mut value = default_value(subxt.types(), type_id);
    if let ValueDef::Composite(Composite::Named(fields)) = &mut value.value {
        for (name, field) in fields.iter_mut() {
            if name == "revision" {
                *field = ScaleValue::u128(u128::from(revision));
            }
        }
    }
    value
        .encode_as_type(type_id, subxt.types())
        .expect("the root encodes")
}

impl RpcClientT for FakeChain {
    fn request_raw<'a>(
        &'a self,
        method: &'a str,
        params: Option<Box<RawValue>>,
    ) -> RawRpcFuture<'a, Box<RawValue>> {
        self.record(method, params.as_deref());
        let parsed: serde_json::Value = params
            .as_deref()
            .and_then(|params| serde_json::from_str(params.get()).ok())
            .unwrap_or_else(|| json!([]));
        let reply = self.reply(method, &parsed);

        Box::pin(async move {
            Ok(RawValue::from_string(reply.to_string()).expect("the reply is valid JSON"))
        })
    }

    fn subscribe_raw<'a>(
        &'a self,
        sub: &'a str,
        params: Option<Box<RawValue>>,
        _unsub: &'a str,
    ) -> RawRpcFuture<'a, RawRpcSubscription> {
        self.record(sub, params.as_deref());
        assert_eq!(
            sub, "author_submitAndWatchExtrinsic",
            "the fake chain models one subscription"
        );

        let parsed: serde_json::Value = params
            .as_deref()
            .and_then(|params| serde_json::from_str(params.get()).ok())
            .unwrap_or_else(|| json!([]));
        let extrinsic = parsed
            .get(0)
            .and_then(serde_json::Value::as_str)
            .map(|hex_str| {
                hex::decode(hex_str.trim_start_matches("0x")).expect("the extrinsic is hex")
            })
            .expect("a submission carries an extrinsic");
        self.0.submitted.lock().unwrap().push(extrinsic);

        let inclusion = *self.0.inclusion.lock().unwrap();
        // Events are attributed to index zero, matching the single-extrinsic
        // block the fake reports.
        let events = match inclusion {
            Inclusion::FinalizedFailure => system_events("ExtrinsicFailed", 0),
            _ => system_events("ExtrinsicSuccess", 0),
        };
        self.set_storage(
            &hex::decode(system_events_key()).expect("the key is hex"),
            events,
        );

        let status = match inclusion {
            Inclusion::FinalizedSuccess | Inclusion::FinalizedFailure => {
                json!({ "finalized": FINALIZED })
            }
            Inclusion::InBlock => json!({ "inBlock": FINALIZED }),
            Inclusion::Rejected => json!({ "invalid": serde_json::Value::Null }),
        };
        let items = vec![Ok(
            RawValue::from_string(status.to_string()).expect("the status is valid JSON")
        )];

        Box::pin(async move {
            Ok(RawRpcSubscription {
                stream: Box::pin(futures::stream::iter(items)),
                id: Some("fake".to_string()),
            })
        })
    }
}
