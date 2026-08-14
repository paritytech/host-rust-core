//! Classification of login failures into [`LoginFailureKind`].
//!
//! A wallet reports why it refused pairing as prose, over
//! `EncryptedResponse::Failed` on the inter-host wire, so the core recovers the
//! discriminant here instead of leaving every host to pattern-match the text.
//! The wording the wallet sends originates from this workspace's own
//! `SlotError` `Display` impls, and the tests below pin the classifier to them:
//! rewording one fails here rather than silently turning a host's fast-fail
//! back into a retry loop.

use truapi_platform::LoginFailureKind;

/// Markers that identify an exhausted statement-store allowance period. Every
/// `SlotError` variant that means "no slot is available to take" renders one of
/// these.
const NO_FREE_SLOT_MARKERS: &[&str] = &["no free statementstore slot", "no free long-term-storage"];

/// Recover the failure kind from a wallet-reported reason.
pub(crate) fn classify_login_failure(reason: &str) -> LoginFailureKind {
    let reason = reason.to_ascii_lowercase();
    if NO_FREE_SLOT_MARKERS
        .iter()
        .any(|marker| reason.contains(marker))
    {
        return LoginFailureKind::NoFreeAllowanceSlots;
    }
    LoginFailureKind::Other
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::runtime::statement_allowance::slot::SlotError;

    #[test]
    fn exhausted_allowance_periods_are_recognized_from_their_own_display_text() {
        for error in [
            SlotError::NoFreeStatementStoreSlot { period: 7, max: 8 },
            SlotError::NoFreeLongTermStorageSlot { period: 7, max: 8 },
        ] {
            assert_eq!(
                classify_login_failure(&error.to_string()),
                LoginFailureKind::NoFreeAllowanceSlots,
                "`{error}` must classify as an exhausted allowance period"
            );
        }
    }

    #[test]
    fn other_slot_failures_are_not_reported_as_exhausted_periods() {
        for error in [
            SlotError::LongTermStoragePeriodDurationZero,
            SlotError::ReplacementRefused { period: 7, seq: 3 },
            SlotError::FreeSlotsAwaitingSubmission { period: 7 },
        ] {
            assert_eq!(
                classify_login_failure(&error.to_string()),
                LoginFailureKind::Other,
                "`{error}` is not an exhausted allowance period"
            );
        }
    }

    #[test]
    fn unrelated_reasons_are_other() {
        for reason in [
            "",
            "user rejected pairing",
            "pairing statement-store subscribe failed: timeout",
        ] {
            assert_eq!(
                classify_login_failure(reason),
                LoginFailureKind::Other,
                "`{reason}` is not an exhausted allowance period"
            );
        }
    }
}
