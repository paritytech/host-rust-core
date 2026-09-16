//! Unified [`Pill`] trait.

use crate::versioned::pill::{
    HostPillDeclareError, HostPillDeclareRequest, HostPillDeclareResponse, HostPillWithdrawError,
    HostPillWithdrawRequest, HostPillWithdrawResponse,
};
use crate::{CallContext, CallError};
use crate::{wire, wire_trait};

/// A countdown the host draws on its own surfaces on the product's behalf.
#[wire_trait(id = 19)]
#[crate::async_trait]
pub trait Pill: Send + Sync {
    /// Declare the pill the host draws from `show_from` until `deadline`.
    ///
    /// The host persists the declaration across restarts. Declarations are
    /// keyed: declaring again with a key already in use replaces that
    /// declaration. The host draws the countdown to `deadline`, hides the pill
    /// while the declaring product is the foreground product, opens
    /// `destination` on tap, and at `deadline` withdraws the pill. With
    /// `open_at_deadline` it also opens `destination` then, unless the user
    /// agent is in the background or is holding the user in a state it must not
    /// pull them out of. The user cannot dismiss the pill.
    ///
    /// `destination` is parsed as a [`navigate_to`](crate::api::System::navigate_to)
    /// URL and refused when that would refuse it. A declaration whose
    /// `show_from` is after its `deadline`, or whose `deadline` is zero, is
    /// refused.
    ///
    /// ```ts
    /// const result = await truapi.pill.declarePill({
    ///   key: "game",
    ///   showFrom: 1776143820000n,
    ///   deadline: 1776144000000n,
    ///   destination: "https://example.dot/game",
    ///   title: "Game starting",
    ///   openAtDeadline: true,
    /// });
    /// assert(result.isOk(), "declarePill failed:", result);
    /// console.log("pill declared");
    /// ```
    #[wire(id = 0)]
    async fn declare_pill(
        &self,
        _cx: &CallContext,
        _request: HostPillDeclareRequest,
    ) -> Result<HostPillDeclareResponse, CallError<HostPillDeclareError>> {
        Err(CallError::unavailable())
    }

    /// Withdraw the pill declared with this key.
    ///
    /// Idempotent: succeeds whether the pill is on screen, still pending, past
    /// its deadline, or was never declared.
    ///
    /// ```ts
    /// const result = await truapi.pill.withdrawPill({ key: "game" });
    /// assert(result.isOk(), "withdrawPill failed:", result);
    /// console.log("pill withdrawn");
    /// ```
    #[wire(id = 1)]
    async fn withdraw_pill(
        &self,
        _cx: &CallContext,
        _request: HostPillWithdrawRequest,
    ) -> Result<HostPillWithdrawResponse, CallError<HostPillWithdrawError>> {
        Err(CallError::unavailable())
    }
}
