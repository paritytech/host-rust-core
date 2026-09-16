use parity_scale_codec::{Decode, Encode};

/// Pill declaration.
///
/// The host draws the pill from `show_from` until `deadline`, then withdraws
/// it. Both instants are Unix milliseconds UTC.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct HostPillDeclareRequest {
    /// Product-chosen key. A declaration reusing a live key replaces it.
    pub key: String,
    /// Instant from which the host draws the pill.
    pub show_from: u64,
    /// Instant at which the host withdraws the pill.
    pub deadline: u64,
    /// URL the host opens on tap and at `deadline`, in the form
    /// [`navigate_to`](crate::api::System::navigate_to) accepts.
    pub destination: String,
    /// Text the host draws beside the countdown.
    pub title: String,
    /// Whether the host also opens `destination` at `deadline`. The opening
    /// carries no permission of its own.
    pub open_at_deadline: bool,
}

/// Request to withdraw a declared pill.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct HostPillWithdrawRequest {
    /// The key the pill was declared with.
    pub key: String,
}
