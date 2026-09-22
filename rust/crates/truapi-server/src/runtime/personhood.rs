//! Personhood on the People chain: collections, rings, and membership proofs.
//!
//! The ring-VRF machinery for proving "this is one distinct person", separate
//! from any one thing a proof is spent on. Four callers share it: statement
//! allowance, PGas claims, allowance renewal, and the backend tunnel's
//! personhood handshake.
//!
//! A proof is built the same way for all of them. Derive the entropy for a
//! collection, find a ring that includes its member key, then open against
//! that ring's baked-in `included` prefix, which is the member set the
//! verifier reads a commitment for.

pub mod collection;
pub mod membership;
pub mod proof;
pub mod ring;
