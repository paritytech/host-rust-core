//! What a payer can tell a payee out of band about a payment.
//!
//! `coinage-layer.md` §8.3 and §8.8. A transfer mints the payee's coins directly
//! into accounts the payee named, so the payee can find them on chain — but only
//! if it knows which accounts to look at and when. A memo carries exactly that,
//! and nothing else: the layer neither encodes nor transmits it, so the caller
//! owns the wire format.
//!
//! Every field here is already public on chain. The transfer that created the
//! coin names both ends of the move in a block, so a memo tells the payee sooner
//! rather than telling it something new.

use parity_scale_codec::{Decode, Encode};

use super::types::{CoinAccountId, CoinIndex};

/// One transferred coin, as the payer can describe it to the payee.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Encode, Decode)]
pub struct MemoEntry {
    /// On-chain origin the coin came from: the spending coin's account for a
    /// coin-origin transfer, or the recycler entry's contextual alias for a coin
    /// minted by an unload.
    ///
    /// Both are 32-byte identifiers the transaction already carries in public, and
    /// both answer the same question — where this coin came from.
    pub sender_coin_account: CoinAccountId,
    /// Account the coin was minted into. The payee recognizes this one.
    pub recipient_account: CoinAccountId,
    /// The payer's own derivation index for the origin coin.
    ///
    /// Present because §8.3 names it; the payee has no use for it, and the layer
    /// does not read it back. See `coinage-rfc-notes.md`: which side's index this
    /// field is meant to carry is not settled, and a payee-side index would have to
    /// be supplied by the caller rather than derived here.
    pub derivation_index: CoinIndex,
}

/// How a set of memo entries lines up with what this layer holds (§8.8).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PaymentClassification {
    /// Every entry's recipient account corresponds to a coin in a purse this
    /// layer knows.
    Matched,
    /// Some do and some do not.
    Received,
    /// None do. An empty entry list lands here.
    Unmatched,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_memo_entry_round_trips_through_scale() {
        // The caller owns the wire format, but the type has to survive being put
        // on one.
        let entry = MemoEntry {
            sender_coin_account: CoinAccountId([1; 32]),
            recipient_account: CoinAccountId([2; 32]),
            derivation_index: CoinIndex(7),
        };

        let encoded = entry.encode();
        assert_eq!(
            MemoEntry::decode(&mut &encoded[..]).expect("decodes"),
            entry
        );
    }
}
