//! Value types shared across the coinage layer.
//!
//! Amounts are dotUSD cents. The layer works in `u64` internally so that sums
//! over a purse cannot overflow at any denomination it supports; the product
//! wire type is narrower, so [`Amount::to_wire`] is fallible.

use core::fmt;
use core::iter::Sum;
use core::time::Duration;

use parity_scale_codec::{Decode, Encode};
use zeroize::{Zeroize, ZeroizeOnDrop};

/// Largest denomination exponent the layer's arithmetic supports.
///
/// A coin of exponent `e` is worth `2^e` cents, so this bounds a single coin at
/// `2^40` cents and leaves room for millions of them to sum inside `u64`. It is
/// a ceiling on what the code can represent, deliberately far above any
/// plausible runtime: the operative limit is the chain's `MaximumExponent`,
/// carried in [`super::chain_constants::CoinageChainConstants`].
pub const MAX_SUPPORTED_DENOMINATION_EXPONENT: i8 = 40;

/// Identifier of a purse within the layer.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Encode, Decode)]
pub struct PurseId(pub u32);

impl PurseId {
    /// Reserved identifier of the main purse, which exists by construction once
    /// the layer is initialized and can never be deleted.
    pub const MAIN: Self = Self(0);

    /// Whether this identifier addresses the main purse.
    pub fn is_main(self) -> bool {
        self == Self::MAIN
    }
}

impl fmt::Display for PurseId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "purse#{}", self.0)
    }
}

/// A dotUSD amount, counted in cents.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Default, Encode, Decode)]
pub struct Amount(u64);

impl Amount {
    /// The zero amount.
    pub const ZERO: Self = Self(0);

    /// Construct an amount from a count of cents.
    pub const fn from_cents(cents: u64) -> Self {
        Self(cents)
    }

    /// The amount as a count of cents.
    pub const fn cents(self) -> u64 {
        self.0
    }

    /// Whether the amount is zero.
    pub const fn is_zero(self) -> bool {
        self.0 == 0
    }

    /// Add two amounts, returning `None` on overflow.
    pub fn checked_add(self, other: Self) -> Option<Self> {
        self.0.checked_add(other.0).map(Self)
    }

    /// Subtract `other`, returning `None` if it exceeds `self`.
    pub fn checked_sub(self, other: Self) -> Option<Self> {
        self.0.checked_sub(other.0).map(Self)
    }

    /// Subtract `other`, saturating at zero.
    pub fn saturating_sub(self, other: Self) -> Self {
        Self(self.0.saturating_sub(other.0))
    }

    /// Narrow to the `u32` cent count used by the product wire types, returning
    /// `None` if the amount does not fit.
    pub fn to_wire(self) -> Option<u32> {
        u32::try_from(self.0).ok()
    }
}

impl fmt::Display for Amount {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{} cents", self.0)
    }
}

impl Sum for Amount {
    fn sum<I: Iterator<Item = Self>>(iter: I) -> Self {
        // Saturating: callers bound denominations by `MAX_SUPPORTED_DENOMINATION_EXPONENT`,
        // so a real purse cannot reach `u64::MAX`, and a saturated balance is
        // preferable to a panic in a display path.
        iter.fold(Self::ZERO, |acc, item| Self(acc.0.saturating_add(item.0)))
    }
}

/// Denomination of a coin or recycler entry, as a power-of-two exponent over
/// cents.
///
/// Signed, because the pallet's `CoinValue` is `i8` and a runtime could in
/// principle configure a `MinimumExponent` below zero. This layer rejects
/// negative exponents: [`Amount`] counts whole cents, so a sub-cent
/// denomination has no representation here. Should a runtime ever ship one, that
/// shows up as a loud construction failure rather than a silently truncated
/// balance.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Encode, Decode)]
pub struct DenominationExponent(i8);

impl DenominationExponent {
    /// Construct a denomination, rejecting sub-cent exponents and anything above
    /// [`MAX_SUPPORTED_DENOMINATION_EXPONENT`].
    pub fn new(exponent: i8) -> Option<Self> {
        (0..=MAX_SUPPORTED_DENOMINATION_EXPONENT)
            .contains(&exponent)
            .then_some(Self(exponent))
    }

    /// The raw exponent, in the pallet's `CoinValue` representation.
    pub const fn get(self) -> i8 {
        self.0
    }

    /// The denomination's value, `2^exponent` cents.
    pub const fn value(self) -> Amount {
        Amount(1u64 << self.0 as u32)
    }
}

impl fmt::Display for DenominationExponent {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "2^{}", self.0)
    }
}

/// Derivation index of a coin within its purse.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, PartialOrd, Ord, Hash, Encode, Decode)]
pub struct CoinIndex(pub u32);

/// Derivation index of a recycler entry within its purse.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, PartialOrd, Ord, Hash, Encode, Decode)]
pub struct EntryIndex(pub u32);

/// Index of a recycler ring on chain.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Encode, Decode)]
pub struct RingIndex(pub u32);

/// Revision of a recycler ring. A ring's membership is versioned, and a proof is
/// only valid against the revision it was built for.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Encode, Decode)]
pub struct RevisionIndex(pub u32);

/// Where a recycler entry sits on chain.
///
/// Both halves are needed to unload: the pallet's `unload_recycler_into_coins`
/// takes the ring index and its revision, and a membership proof built against
/// one revision does not verify against another.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Encode, Decode)]
pub struct RingLocation {
    /// The ring the entry joined.
    pub index: RingIndex,
    /// The membership revision the entry was observed at.
    pub revision: RevisionIndex,
}

impl RingLocation {
    /// A location from its raw parts.
    pub const fn new(index: RingIndex, revision: RevisionIndex) -> Self {
        Self { index, revision }
    }
}

/// Number of transfers or splits a coin has undergone. The chain caps this;
/// past the cap the coin is unusable.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Default, Encode, Decode)]
pub struct CoinAge(pub u16);

/// A wall-clock instant, in milliseconds since the Unix epoch.
///
/// The domain layer never reads a clock; instants are supplied by the caller so
/// that behaviour is reproducible under test.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Encode, Decode)]
pub struct Timestamp(pub u64);

impl Timestamp {
    /// The instant a Unix-seconds value from the chain names.
    ///
    /// The pallet stores lock expiries in whole seconds; this layer counts
    /// milliseconds, and mixing the two silently makes a lock look 1000 times
    /// shorter than it is.
    pub const fn from_unix_seconds(seconds: u64) -> Self {
        Self(seconds.saturating_mul(1_000))
    }

    /// The instant `duration` after this one, saturating at `u64::MAX`.
    pub fn saturating_add(self, duration: Duration) -> Self {
        Self(self.0.saturating_add(duration.as_millis() as u64))
    }

    /// The instant `duration` before this one, saturating at zero.
    pub fn saturating_sub(self, duration: Duration) -> Self {
        Self(self.0.saturating_sub(duration.as_millis() as u64))
    }
}

/// On-chain account holding a coin.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Encode, Decode)]
pub struct CoinAccountId(pub [u8; 32]);

/// The secret controlling a coin, as it crosses the layer's API.
///
/// The only cryptographic material the layer hands out or takes in: §12.1 forbids
/// the rest, and §8.4 makes export the single exception. 64 bytes, the sr25519
/// secret's own encoding.
///
/// Zeroized on drop, and never rendered — a `Debug` that printed it would put a
/// spendable coin into every log line that touched an export.
#[derive(Clone, Encode, Decode, Zeroize, ZeroizeOnDrop)]
pub struct CoinSecret(pub [u8; 64]);

impl fmt::Debug for CoinSecret {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("CoinSecret(<redacted>)")
    }
}

impl PartialEq for CoinSecret {
    /// Constant-time: comparing a secret byte by byte leaks its prefix through
    /// timing.
    fn eq(&self, other: &Self) -> bool {
        self.0
            .iter()
            .zip(other.0.iter())
            .fold(0u8, |differences, (left, right)| {
                differences | (left ^ right)
            })
            == 0
    }
}

impl Eq for CoinSecret {}

/// Hash of a submitted extrinsic.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Encode, Decode)]
pub struct ExtrinsicHash(pub [u8; 32]);

/// Hash of a block.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Encode, Decode)]
pub struct BlockHash(pub [u8; 32]);

/// Opaque, durable identifier of a long-running operation.
///
/// Handles are issued by the layer and increase monotonically, which gives
/// deterministic ordering in tests and in recovery.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Encode, Decode)]
pub struct OperationHandle(pub u64);

impl fmt::Display for OperationHandle {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "op#{}", self.0)
    }
}

/// Monotonic allocator for [`OperationHandle`]s.
#[derive(Debug, Clone, Default, Encode, Decode)]
pub struct OperationHandleAllocator {
    next: u64,
}

impl OperationHandleAllocator {
    /// Issue the next handle.
    pub fn allocate(&mut self) -> OperationHandle {
        let handle = OperationHandle(self.next);
        self.next += 1;
        handle
    }

    /// The handle that will be issued next, without issuing it.
    pub fn peek(&self) -> OperationHandle {
        OperationHandle(self.next)
    }
}

/// The kinds of long-running operation the layer supports.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Encode, Decode)]
pub enum OperationKind {
    /// Fund a purse from an external account.
    TopUp,
    /// Send value to pre-arranged recipient coin accounts.
    Transfer,
    /// Hand coin secrets to the upper layer.
    Export,
    /// Route externally supplied coin secrets into a purse.
    Import,
    /// Send value out of coinage to a non-coinage account.
    ExternalOffload,
    /// Move value between two purses.
    Rebalance,
    /// Run the coin-age and ring-expiration sweeps.
    MaintenanceSweep,
    /// Drain a purse into another and close it.
    DeletePurse,
    /// Rebuild durable records by scanning the chain.
    Recover,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn main_purse_is_the_reserved_identifier() {
        assert!(PurseId::MAIN.is_main());
        assert!(!PurseId(1).is_main());
        assert_eq!(PurseId::MAIN, PurseId(0));
    }

    #[test]
    fn denomination_value_is_two_to_the_exponent() {
        let two_cents = DenominationExponent::new(1).expect("1 is in range");
        assert_eq!(two_cents.value(), Amount::from_cents(2));

        let largest = DenominationExponent::new(MAX_SUPPORTED_DENOMINATION_EXPONENT)
            .expect("ceiling is valid");
        assert_eq!(
            largest.value(),
            Amount::from_cents(1u64 << MAX_SUPPORTED_DENOMINATION_EXPONENT)
        );
    }

    #[test]
    fn denomination_rejects_exponents_above_the_ceiling() {
        assert!(DenominationExponent::new(MAX_SUPPORTED_DENOMINATION_EXPONENT + 1).is_none());
    }

    #[test]
    fn amount_arithmetic_is_checked() {
        let five = Amount::from_cents(5);
        let three = Amount::from_cents(3);

        assert_eq!(five.checked_add(three), Some(Amount::from_cents(8)));
        assert_eq!(five.checked_sub(three), Some(Amount::from_cents(2)));
        assert_eq!(three.checked_sub(five), None);
        assert_eq!(three.saturating_sub(five), Amount::ZERO);
        assert_eq!(Amount::from_cents(u64::MAX).checked_add(five), None);
    }

    #[test]
    fn amount_narrows_to_the_wire_type_only_when_it_fits() {
        assert_eq!(Amount::from_cents(42).to_wire(), Some(42));
        assert_eq!(
            Amount::from_cents(u64::from(u32::MAX)).to_wire(),
            Some(u32::MAX)
        );
        assert_eq!(Amount::from_cents(u64::from(u32::MAX) + 1).to_wire(), None);
    }

    #[test]
    fn summing_a_purse_of_max_denomination_coins_does_not_overflow() {
        let largest = DenominationExponent::new(MAX_SUPPORTED_DENOMINATION_EXPONENT)
            .expect("ceiling is valid");
        let total: Amount = core::iter::repeat_n(largest.value(), 1_000).sum();
        assert_eq!(
            total.cents(),
            1_000 * (1u64 << MAX_SUPPORTED_DENOMINATION_EXPONENT)
        );
    }

    #[test]
    fn handles_are_monotonic() {
        let mut allocator = OperationHandleAllocator::default();
        let first = allocator.allocate();
        let second = allocator.allocate();

        assert!(second > first);
        assert_eq!(allocator.peek(), OperationHandle(2));
    }
}
