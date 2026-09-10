//! Versioned wrappers for [`Scarcity`](crate::api::Scarcity) methods.

use crate::v01;

truapi_macros::versioned_type! {
    pub enum HostScarcityListRequest { V1 => v01::HostScarcityListRequest }
    pub enum HostScarcityListResponse { V1 => v01::HostScarcityListResponse }
    pub enum HostScarcityListError { V1 => v01::ScarcityError }
    pub enum HostScarcityListSubscribeRequest { V1 => v01::HostScarcityListSubscribeRequest }
    pub enum HostScarcityListSubscribeItem { V1 => v01::HostScarcityListSubscribeItem }
    pub enum HostScarcityListSubscribeError { V1 => v01::ScarcityError }
    pub enum HostScarcityRequestReceiveAddressRequest { V1 => v01::HostScarcityRequestReceiveAddressRequest }
    pub enum HostScarcityRequestReceiveAddressResponse { V1 => v01::HostScarcityRequestReceiveAddressResponse }
    pub enum HostScarcityRequestReceiveAddressError { V1 => v01::ScarcityError }
    pub enum HostScarcityTransferRequest { V1 => v01::HostScarcityTransferRequest }
    pub enum HostScarcityTransferItem { V1 => v01::ScarcityTransferStatus }
    pub enum HostScarcityTransferError { V1 => v01::ScarcityError }
}
