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
/// whose OS grant was revoked answers `granted: false` without a prompt. An OS
/// grant that is merely undetermined does not change the answer, because the OS
/// resolves its own gate when the capability is used.
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
    /// Outbound access to one method and path on one domain, carrying a
    /// personhood proof the host attaches (RFC 0025).
    ///
    /// Appended last on purpose. This enum is SCALE-encoded into the persisted
    /// permission key, so changing an existing variant would invalidate every
    /// decision a user has already made.
    #[display("{method} {domain}{path}")]
    Credential {
        /// Domain the grant covers. Covered requests must be `https`, since
        /// the proof would otherwise travel in plaintext.
        domain: String,
        /// Exact path the grant covers. No wildcards.
        path: String,
        /// HTTP method the grant covers.
        method: String,
    },
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

#[cfg(test)]
mod tests {
    use super::*;

    /// RFC 0025 appends `Credential` rather than amending `Remote`, because
    /// this enum is SCALE-encoded into the persisted permission key. Pin every
    /// discriminant: a reorder silently invalidates decisions users already made.
    #[test]
    fn remote_permission_discriminants_are_pinned() {
        assert_eq!(
            RemotePermission::Remote { domains: vec![] }.encode()[0],
            0,
            "Remote must stay at index 0"
        );
        assert_eq!(RemotePermission::WebRtc.encode()[0], 1);
        assert_eq!(RemotePermission::ChainSubmit.encode()[0], 2);
        assert_eq!(RemotePermission::PreimageSubmit.encode()[0], 3);
        assert_eq!(RemotePermission::StatementSubmit.encode()[0], 4);
        assert_eq!(
            RemotePermission::Credential {
                domain: "onramp.example.com".into(),
                path: "/session".into(),
                method: "POST".into(),
            }
            .encode()[0],
            5,
            "Credential must be appended last"
        );
    }

    /// A grant stored before RFC 0025, encoded by the previous definition, must
    /// still decode to the same value. These bytes are literal on purpose: a
    /// round trip through the current code would pass even if the shape moved.
    #[test]
    fn grant_stored_before_this_rfc_still_decodes() {
        // Remote { domains: ["example.com"] }: variant 0, Vec len 1, str len 11.
        let stored: Vec<u8> = [&[0u8, 0x04, 0x2c][..], b"example.com"].concat();

        let decoded = RemotePermission::decode(&mut &stored[..]).expect("pre-RFC grant decodes");
        assert_eq!(
            decoded,
            RemotePermission::Remote {
                domains: vec!["example.com".to_string()],
            }
        );
    }

    #[test]
    fn credential_round_trips_and_displays() {
        let original = RemotePermission::Credential {
            domain: "onramp.example.com".into(),
            path: "/meld/session".into(),
            method: "POST".into(),
        };
        let decoded =
            RemotePermission::decode(&mut &original.encode()[..]).expect("Credential decodes");
        assert_eq!(decoded, original);
        assert_eq!(
            original.to_string(),
            "POST onramp.example.com/meld/session",
            "the prompt names the operation"
        );
    }
}
