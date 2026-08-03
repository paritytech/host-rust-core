//! The coinage layer: the host's self-contained coinage subsystem.
//!
//! The layer owns every coin and recycler entry the user controls, partitions
//! them across purses, and runs selection, recycling, and the operation
//! lifecycle. It knows nothing about receivables, cheques, or refunds; those
//! compose above it out of the coin export/import seam.
//!
//! This module tree is the pure domain model: records, state machines, the
//! arithmetic over them, and key derivation. It performs no chain access, no
//! persistence, and no time lookups — wall-clock instants and jitter draws are
//! supplied by the caller, so the whole state machine is exercisable without a
//! host or a chain. Signing, submission, and subscriptions live in
//! `runtime::coinage`.

pub mod chain_constants;
pub mod coin;
pub mod derivation;
pub mod entry;
pub mod error;
pub mod event;
pub mod operation;
pub mod params;
pub mod purse;
pub mod selection;
pub mod store;
pub mod types;
pub mod unload_token;
