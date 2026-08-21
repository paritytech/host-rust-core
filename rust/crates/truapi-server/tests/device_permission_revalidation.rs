//! Wiring test for OS revalidation of device permissions.
//!
//! The decision matrix itself is unit-tested in
//! `truapi_server::host_logic::permissions`. What that cannot reach is the path
//! a real request takes: a product frame through the generated dispatcher into
//! the runtime, which has to hand the permission service the adapter installed
//! on the host runtime. A break anywhere along it — an installer that stores
//! nothing, a runtime that builds the service without the adapter — leaves
//! every unit test passing while no request is ever revalidated.
//!
//! So both cases below drive a real `permissions_request_device_permission`
//! frame against a platform whose prompt grants unconditionally, and separate
//! them only by whether an adapter reporting an OS refusal is installed.

use std::sync::{Arc, Mutex};

use parity_scale_codec::{Decode, Encode};

use truapi::v01;
use truapi::versioned::permissions::{HostDevicePermissionRequest, HostDevicePermissionResponse};
use truapi_platform::{DevicePermissionStatus, PermissionStatusHost};
use truapi_server::frame::{Payload, ProtocolMessage, request_ids};
use truapi_server::{FrameSink, PairingHostRuntime};

// Shared harness; this binary uses only part of it.
#[allow(dead_code)]
mod common;
use common::{WireShapePlatform, test_runtime_config, test_spawner};

/// Frame sink that keeps every emitted frame in send order.
#[derive(Default)]
struct RecordingSink {
    frames: Mutex<Vec<Vec<u8>>>,
}

impl FrameSink for RecordingSink {
    fn emit_frame(&self, frame: Vec<u8>) {
        self.frames.lock().unwrap().push(frame);
    }
}

/// Status adapter that reports one fixed answer for every capability.
struct FixedStatus(DevicePermissionStatus);

#[truapi_platform::async_trait]
impl PermissionStatusHost for FixedStatus {
    async fn device_permission_status(
        &self,
        _request: v01::HostDevicePermissionRequest,
    ) -> Result<DevicePermissionStatus, v01::GenericError> {
        Ok(self.0)
    }
}

/// Drive one camera request through the dispatcher and return what the product
/// is told. `status` is installed on the host runtime when present.
fn request_camera(status: Option<Arc<dyn PermissionStatusHost>>) -> bool {
    let (host_config, product) = test_runtime_config();
    let runtime = PairingHostRuntime::new(Arc::new(WireShapePlatform), host_config, test_spawner());
    if let Some(status) = status {
        assert!(
            runtime.set_permission_status_host(status),
            "the adapter must install on a fresh runtime",
        );
    }

    let sink = Arc::new(RecordingSink::default());
    let product_runtime = runtime.product_runtime(product, sink.clone());

    let ids = request_ids("permissions_request_device_permission").expect("known request method");
    let frame = ProtocolMessage {
        request_id: "p:1".into(),
        payload: Payload {
            id: ids.request_id,
            value: HostDevicePermissionRequest::V1(v01::HostDevicePermissionRequest::Camera)
                .encode(),
        },
    };
    futures::executor::block_on(product_runtime.receive_frame(frame.encode()))
        .expect("dispatcher accepted the frame");

    let frames = sink.frames.lock().unwrap().clone();
    let response = frames
        .iter()
        .map(|bytes| ProtocolMessage::decode(&mut &bytes[..]).expect("decode emitted frame"))
        .find(|message| message.payload.id == ids.response_id)
        .expect("dispatcher emitted a device-permission response");

    // Wire payload is [version disc][result disc][body]; the versioned
    // response decodes from the version byte and the body alone.
    let payload = &response.payload.value;
    assert_eq!(payload[1], 0x00, "expected an Ok result, got {payload:?}");
    let mut versioned = vec![payload[0]];
    versioned.extend_from_slice(&payload[2..]);
    let HostDevicePermissionResponse::V1(decoded) =
        HostDevicePermissionResponse::decode(&mut &versioned[..]).expect("decode response body");
    decoded.granted
}

#[test]
fn a_prompt_that_grants_is_reported_as_granted() {
    // Control. `WireShapePlatform` grants every device prompt, so this fixes
    // what the next case is measured against: the same request, same platform,
    // and the only difference is the installed adapter.
    assert!(request_camera(None));
}

#[test]
fn an_os_refusal_reaches_the_product_as_a_denial() {
    assert!(!request_camera(Some(Arc::new(FixedStatus(
        DevicePermissionStatus::Denied
    )))));
}

#[test]
fn an_os_status_of_not_applicable_leaves_the_prompt_deciding() {
    // A host that serves the capability but has no OS gate for it must not
    // have its grants suppressed.
    assert!(request_camera(Some(Arc::new(FixedStatus(
        DevicePermissionStatus::NotApplicable
    )))));
}
