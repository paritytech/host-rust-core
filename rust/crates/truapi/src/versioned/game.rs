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
        let busy = HostRemindNextGameError::V1(v01::HostRemindNextGameError::Busy);
        let unknown = HostRemindNextGameError::V1(v01::HostRemindNextGameError::Unknown {
            reason: "x".to_string(),
        });

        assert_eq!(hex::encode(past.encode()), "0000");
        assert_eq!(hex::encode(denied.encode()), "0001");
        assert_eq!(hex::encode(busy.encode()), "0002");
        assert_eq!(hex::encode(unknown.encode()), "00030478");
    }
}
