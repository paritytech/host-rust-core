use derive_more::Display;
use parity_scale_codec::{Decode, Encode};

/// Device-capability permission requested from the host (RFC 0002).
///
/// The user's decision is persisted indefinitely after the first prompt and
/// survives app restarts, whether the decision was grant or deny; the host
/// does not re-prompt on subsequent requests for the same capability.
///
/// That decision is about this product. The OS grant behind it belongs to the
/// host application and can move independently, so a host that can read OS
/// state has the capability resolve only while both allow it: a stored grant
/// whose OS grant was revoked answers `granted: false` without a prompt, and
/// one the platform has reset prompts again to reach the OS dialog.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Encode, Decode, Display)]
#[allow(clippy::upper_case_acronyms)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Enum))]
pub enum HostDevicePermissionRequest {
    /// Showing system notifications.
    #[display("notifications")]
    Notifications,
    /// Camera capture access.
    #[display("camera")]
    Camera,
    /// Microphone capture access.
    #[display("microphone")]
    Microphone,
    /// Bluetooth device access.
    #[display("bluetooth")]
    Bluetooth,
    /// NFC reader access.
    #[display("NFC")]
    NFC,
    /// Geolocation access.
    #[display("location")]
    Location,
    /// Clipboard access.
    #[display("clipboard")]
    Clipboard,
    /// Handing a URL to the operating system, leaving the host application
    /// entirely. Requestable and persistable, but the core enforces nothing with
    /// it: *which* hosts a product may send the user to is
    /// `RemotePermission::Remote`, wherever the destination ends up opening.
    #[display("open URL")]
    OpenUrl,
    /// Biometric authentication.
    #[display("biometrics")]
    Biometrics,
}

/// One remote-operation permission requested by the product (RFC 0002).
///
/// `ChainSubmit`, `PreimageSubmit`, and `StatementSubmit` are also triggered
/// implicitly by the corresponding business calls when not yet granted.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode, Display)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Enum))]
pub enum RemotePermission {
    /// Reaching a set of domains: outbound HTTP/WebSocket access, and sending
    /// the user out to one of them with `navigate_to`.
    ///
    /// One grant per host covers both, because both hand the same third party
    /// the same thing: that the user is here, and whatever the product puts in
    /// the URL. Splitting them would put the same question to the user twice.
    #[display("access to {}", domains.join(", "))]
    Remote {
        /// Domain patterns requested by the product. Each is an exact host, a
        /// single-level wildcard (`*.example.com`), or `*` for any host.
        domains: Vec<String>,
    },
    /// WebRTC access.
    ///
    /// Enforced inside the product's own realm rather than at a network layer:
    /// ICE reaches an arbitrary host over UDP, so no content rule list, request
    /// interceptor, or CSP directive observes it. A host peeks this decision
    /// before the product realm exists and the lockdown container removes
    /// `RTCPeerConnection` — and its vendor-prefixed aliases — unless the answer
    /// was an explicit grant. Resolving it up front is what makes the gate
    /// unforgeable, and it means a fresh grant applies from the next load.
    ///
    /// Camera and microphone capture is gated by the OS permission prompts and
    /// [`HostDevicePermissionRequest`], not by this permission.
    #[display("WebRTC connections")]
    WebRtc,
    /// Submitting transactions on behalf of the user via `remote_chain_transaction_broadcast`.
    #[display("submit chain transactions")]
    ChainSubmit,
    /// Submitting preimages on behalf of the user via `remote_preimage_submit`.
    #[display("submit preimages")]
    PreimageSubmit,
    /// Submitting statements on behalf of the user via `remote_statement_store_submit`.
    #[display("submit statements")]
    StatementSubmit,
}

/// remote-permission request (RFC 0002).
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode, Display)]
#[display("{permission}")]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct RemotePermissionRequest {
    /// Permission requested by the product.
    pub permission: RemotePermission,
}

/// Outcome of a device-permission request.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub struct HostDevicePermissionResponse {
    /// Whether the permission was granted.
    pub granted: bool,
}

/// Outcome of a remote-permission request.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub struct RemotePermissionResponse {
    /// Whether the permission was granted.
    pub granted: bool,
}
