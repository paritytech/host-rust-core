//! Versioned wrappers for [`Locale`](crate::api::Locale) methods.

use crate::v01;

truapi_macros::versioned_type! {
    pub enum HostLocaleSubscribeItem { V1 => v01::HostLocaleSubscribeItem }
}
