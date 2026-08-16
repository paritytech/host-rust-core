use derive_more::Display;
use parity_scale_codec::{Decode, Encode};

use super::common::GenericError;

/// Request to query whether a feature is supported by the host.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Enum))]
pub enum HostFeatureSupportedRequest {
    /// Ask whether the host can interact with the chain identified by genesis hash.
    Chain {
        /// Chain genesis hash.
        genesis_hash: Vec<u8>,
    },
    /// Ask whether `id` opens a method on this host build (RFC 0027).
    ///
    /// `id` is a request discriminant or a product-facing
    /// subscription-start discriminant — the two frame kinds a product can
    /// begin a call with. Variant index 1; a host that cannot decode it
    /// answers `CallError::MalformedFrame`, which is RFC 0027's no-support
    /// signal. `Chain` stays variant index 0.
    Method {
        /// Request or subscription-start discriminant from the wire table.
        id: u8,
    },
}

/// Error from [`crate::api::System::navigate_to`].
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode, Display)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Enum))]
pub enum HostNavigateToError {
    /// User denied the navigation prompt.
    #[display("navigation denied by user")]
    PermissionDenied,
    /// Catch-all.
    #[display("{reason}")]
    Unknown {
        /// Human-readable failure reason.
        reason: String,
    },
}

/// Error from [`crate::api::System::handshake`] (RFC 0009).
///
/// The handshake is the first call on a fresh connection; it does not require
/// user authentication and is used to negotiate the wire codec version.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub enum HostHandshakeError {
    /// Host did not complete the handshake in time.
    Timeout,
    /// Host does not speak the codec version requested by the product.
    UnsupportedProtocolVersion,
    /// Catch-all.
    Unknown(GenericError),
}

/// Wire-codec negotiation payload sent by the product (RFC 0009).
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub struct HostHandshakeRequest {
    /// Wire codec version requested by the product.
    pub codec_version: u8,
}

/// Response to a feature-support query.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub struct HostFeatureSupportedResponse {
    /// Whether the feature is supported.
    pub supported: bool,
}

#[cfg(test)]
mod tests {
    use parity_scale_codec::{Decode, Encode};

    use super::HostFeatureSupportedRequest;

    #[test]
    fn chain_keeps_variant_index_zero() {
        let encoded = HostFeatureSupportedRequest::Chain {
            genesis_hash: vec![0u8; 32],
        }
        .encode();
        assert_eq!(encoded.first(), Some(&0x00));
    }

    #[test]
    fn every_method_id_round_trips_at_variant_index_one() {
        for id in 0..=u8::MAX {
            let value = HostFeatureSupportedRequest::Method { id };
            let encoded = value.encode();
            assert_eq!(encoded, vec![0x01, id]);
            assert_eq!(
                HostFeatureSupportedRequest::decode(&mut &encoded[..]).expect("decode"),
                value
            );
        }
    }
}

/// Request to navigate the host to an external URL.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub struct HostNavigateToRequest {
    /// URL to open.
    pub url: String,
}
