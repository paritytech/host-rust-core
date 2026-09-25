use parity_scale_codec::{Decode, Encode};

/// Request to remind the user when this product's next game starts.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub struct HostRemindNextGameRequest {
    /// Milliseconds since the Unix epoch, UTC, at which the game starts.
    pub starts_at: u64,
}

/// Why a reminder was not taken.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub enum HostRemindNextGameError {
    /// `starts_at` is not after the device's current time.
    StartsInPast,
    /// The user did not allow this product to remind them, or the OS allows
    /// neither alarms nor notifications.
    PermissionDenied,
    /// Catch-all.
    Unknown {
        /// Human-readable reason.
        reason: String,
    },
}

/// Request to drop this product's reminder.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub struct HostCancelNextGameRequest {}
