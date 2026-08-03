//! Chain-facing coinage orchestration.
//!
//! The domain model lives in [`crate::host_logic::coinage`] and knows nothing
//! about extrinsics. This tree turns its plans into pallet calls, signs and
//! submits them, and feeds chain observations back in.
//!
//! Coinage needs key material, so it is a signing-host concern: a seedless
//! pairing host forwards these operations rather than performing them.

pub mod call;
pub mod extension;
pub mod proof;
