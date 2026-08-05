//! TrUAPI Protocol v0.1 type definitions.

/// A 32-byte value, passed as plain bytes on FFI surfaces.
pub type Bytes32 = [u8; 32];

#[cfg(feature = "uniffi")]
uniffi::custom_type!(Bytes32, Vec<u8>, {
    remote,
    lower: |bytes| bytes.to_vec(),
    try_lift: |bytes| Ok(bytes.as_slice().try_into()?),
});

mod account;
mod chain;
mod chat;
mod coin_payment;
mod common;
mod entropy;
mod local_storage;
mod notifications;
mod payment;
mod permissions;
mod preimage;
mod resource_allocation;
mod signing;
mod statement_store;
mod system;
mod theme;
mod transaction;

pub use account::*;
pub use chain::*;
pub use chat::*;
pub use coin_payment::*;
pub use common::*;
pub use entropy::*;
pub use local_storage::*;
pub use notifications::*;
pub use payment::*;
pub use permissions::*;
pub use preimage::*;
pub use resource_allocation::*;
pub use signing::*;
pub use statement_store::*;
pub use system::*;
pub use theme::*;
pub use transaction::*;
