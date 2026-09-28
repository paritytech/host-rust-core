//! Versioned wrappers for [`Game`](crate::api::Game) methods.

use crate::v01;

truapi_macros::versioned_type! {
    pub enum HostRemindNextGameRequest { V1 => v01::HostRemindNextGameRequest }
    pub enum HostRemindNextGameResponse { V1 }
    pub enum HostRemindNextGameError { V1 => v01::HostRemindNextGameError }
    pub enum HostCancelNextGameRequest { V1 => v01::HostCancelNextGameRequest }
    pub enum HostCancelNextGameResponse { V1 }
    pub enum HostCancelNextGameError { V1 => v01::GenericError }
}

#[cfg(test)]
mod tests {
    use super::*;
    use parity_scale_codec::Encode;

    // A product tells a past start apart from a refusal by discriminant, so
    // the order of the domain errors is part of the wire contract.
    #[test]
    fn remind_errors_keep_their_discriminants() {
        let past = HostRemindNextGameError::V1(v01::HostRemindNextGameError::StartsInPast);
        let denied = HostRemindNextGameError::V1(v01::HostRemindNextGameError::PermissionDenied);

        assert_eq!(hex::encode(past.encode()), "0000");
        assert_eq!(hex::encode(denied.encode()), "0001");
    }

    // The empty cancel request carries no bytes beyond its envelope tag, the
    // same encoding a bare `V1` would have.
    #[test]
    fn the_cancel_request_encodes_as_its_envelope_tag() {
        let request = HostCancelNextGameRequest::V1(v01::HostCancelNextGameRequest {});

        assert_eq!(hex::encode(request.encode()), "00");
    }
}
