//! Inter-host SSO with the paired wallet: `pairing` bootstraps the
//! QR/deeplink handshake, `messages` carries the session-channel payloads
//! exchanged afterwards, `wire` types the request/response pairing.

pub mod messages;
pub mod pairing;
pub mod wire;
