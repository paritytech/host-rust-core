//! Storage keys and value decoding for the funding arrival watch.
//!
//! Inbound success is the core's own observation, never a provider's claim, so
//! the core reads the destination account's balance itself through
//! `ChainRuntime`. This module is the pure half of that: which storage key to
//! read, how to decode the value, and whether what arrived satisfies the
//! session. Chain I/O lives with the caller, as in
//! [`super::super::identity`].
//!
//! Two storage shapes cover the inbound targets `FundingDelivery::Account`
//! names: a chain's native balance in `System::Account`, and an assets-pallet
//! balance in `Assets::Account`. Both assume the standard pallet names and
//! `Blake2_128Concat` key hashers; a chain that renames either needs its own
//! key builder rather than a tweak to these.

use parity_scale_codec::{Decode, Encode};
use sp_crypto_hashing::{blake2_128, twox_128};

/// Leading fields of a `frame_system::AccountInfo` record.
///
/// Only the free balance is read. `AccountData` continues with reserved,
/// frozen, and flags fields that funding does not consult, and SCALE decoding
/// stops once the fields named here are consumed.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
struct SystemAccountPrefix {
    nonce: u32,
    consumers: u32,
    providers: u32,
    sufficients: u32,
    free: u128,
}

/// Leading fields of a `pallet_assets::AssetAccount` record.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
struct AssetAccountPrefix {
    balance: u128,
}

/// Build the `System::Account` storage key for `account_id`.
pub fn system_account_storage_key(account_id: &[u8; 32]) -> Vec<u8> {
    let mut key = Vec::with_capacity(16 + 16 + 16 + account_id.len());
    key.extend_from_slice(&twox_128(b"System"));
    key.extend_from_slice(&twox_128(b"Account"));
    key.extend_from_slice(&blake2_128(account_id));
    key.extend_from_slice(account_id);
    key
}

/// Build the `Assets::Account` storage key for `(asset_id, account_id)`.
pub fn assets_account_storage_key(asset_id: u32, account_id: &[u8; 32]) -> Vec<u8> {
    let asset_key = asset_id.encode();
    let mut key = Vec::with_capacity(16 + 16 + 16 + asset_key.len() + 16 + account_id.len());
    key.extend_from_slice(&twox_128(b"Assets"));
    key.extend_from_slice(&twox_128(b"Account"));
    key.extend_from_slice(&blake2_128(&asset_key));
    key.extend_from_slice(&asset_key);
    key.extend_from_slice(&blake2_128(account_id));
    key.extend_from_slice(account_id);
    key
}

/// Decode the free balance from a `System::Account` storage value.
pub fn decode_system_free_balance(value: &[u8]) -> Result<u128, String> {
    let mut input = value;
    let decoded = SystemAccountPrefix::decode(&mut input)
        .map_err(|err| format!("invalid System.Account record: {err}"))?;
    Ok(decoded.free)
}

/// Decode the balance from an `Assets::Account` storage value.
pub fn decode_asset_balance(value: &[u8]) -> Result<u128, String> {
    let mut input = value;
    let decoded = AssetAccountPrefix::decode(&mut input)
        .map_err(|err| format!("invalid Assets.Account record: {err}"))?;
    Ok(decoded.balance)
}

/// Decides when an inbound session's funds have arrived.
///
/// Comparison is against the balance recorded when the session opened, so a
/// pre-existing balance is never mistaken for the deposit. An absent storage
/// entry reads as zero, which is what an account that does not exist yet holds.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ArrivalProbe {
    /// Destination balance when the session opened.
    baseline: u128,
    /// Amount the session is waiting for.
    expected: u128,
}

impl ArrivalProbe {
    /// Start watching from `baseline`, waiting for `expected`.
    pub fn new(baseline: u128, expected: u128) -> Self {
        Self { baseline, expected }
    }

    /// Credited amount if the deposit has arrived, else `None`.
    ///
    /// Returns the full increase rather than the expected amount, so a session
    /// that received more than it asked for reports what actually landed —
    /// which is why `Delivered.credited` may differ from the amount sought.
    ///
    /// A decrease yields `None`: the balance moving the wrong way is not an
    /// arrival, and an unrelated debit must not be read as one.
    pub fn credited(&self, current: u128) -> Option<u128> {
        let gained = current.checked_sub(self.baseline)?;
        (gained >= self.expected && gained > 0).then_some(gained)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const ACCOUNT: [u8; 32] = [0x42; 32];

    #[test]
    fn system_account_key_has_the_documented_layout() {
        let key = system_account_storage_key(&ACCOUNT);

        assert_eq!(key.len(), 16 + 16 + 16 + 32);
        assert_eq!(&key[..16], &twox_128(b"System"));
        assert_eq!(&key[16..32], &twox_128(b"Account"));
        assert_eq!(&key[32..48], &blake2_128(&ACCOUNT));
        assert_eq!(&key[48..], &ACCOUNT);
    }

    #[test]
    fn twox128_matches_the_known_system_prefix_vector() {
        // Guards the hasher itself, not just our concatenation.
        assert_eq!(
            hex::encode(twox_128(b"System")),
            "26aa394eea5630e07c48ae0c9558cef7"
        );
        assert_eq!(
            hex::encode(twox_128(b"Account")),
            "b99d880ec681799c0cf30e8886371da9"
        );
    }

    #[test]
    fn assets_account_key_concatenates_both_map_keys() {
        let asset_id = 1337u32;
        let key = assets_account_storage_key(asset_id, &ACCOUNT);

        assert_eq!(key.len(), 16 + 16 + 16 + 4 + 16 + 32);
        assert_eq!(&key[..16], &twox_128(b"Assets"));
        assert_eq!(&key[16..32], &twox_128(b"Account"));
        assert_eq!(&key[32..48], &blake2_128(&asset_id.encode()));
        assert_eq!(&key[48..52], &asset_id.encode()[..]);
        assert_eq!(&key[52..68], &blake2_128(&ACCOUNT));
        assert_eq!(&key[68..], &ACCOUNT);
    }

    #[test]
    fn system_free_balance_is_read_past_the_counter_fields() {
        let record = SystemAccountPrefix {
            nonce: 7,
            consumers: 1,
            providers: 2,
            sufficients: 0,
            free: 9_000_000,
        };

        assert_eq!(
            decode_system_free_balance(&record.encode()),
            Ok(9_000_000u128)
        );
    }

    #[test]
    fn system_free_balance_ignores_trailing_account_data() {
        let mut blob = SystemAccountPrefix {
            nonce: 0,
            consumers: 0,
            providers: 1,
            sufficients: 0,
            free: 500,
        }
        .encode();
        // reserved, frozen, flags — present on chain, unread here.
        blob.extend_from_slice(&[0u8; 48]);

        assert_eq!(decode_system_free_balance(&blob), Ok(500u128));
    }

    #[test]
    fn truncated_system_record_is_an_error_not_a_zero_balance() {
        let failed = decode_system_free_balance(&[0u8; 8]);

        assert!(failed.is_err(), "expected decode failure, got {failed:?}");
    }

    #[test]
    fn asset_balance_reads_the_leading_field() {
        let blob = AssetAccountPrefix { balance: 250 }.encode();

        assert_eq!(decode_asset_balance(&blob), Ok(250u128));
    }

    // --- arrival decision ---

    #[test]
    fn exact_expected_amount_counts_as_arrived() {
        let probe = ArrivalProbe::new(6, 100);

        assert_eq!(probe.credited(106), Some(100));
    }

    #[test]
    fn an_overpayment_reports_what_actually_landed() {
        let probe = ArrivalProbe::new(6, 100);

        assert_eq!(probe.credited(206), Some(200));
    }

    #[test]
    fn a_partial_deposit_is_not_an_arrival() {
        let probe = ArrivalProbe::new(6, 100);

        assert_eq!(probe.credited(56), None);
    }

    #[test]
    fn a_pre_existing_balance_is_not_mistaken_for_the_deposit() {
        let probe = ArrivalProbe::new(500, 100);

        assert_eq!(probe.credited(500), None);
    }

    #[test]
    fn a_balance_decrease_is_not_an_arrival() {
        let probe = ArrivalProbe::new(500, 100);

        assert_eq!(probe.credited(200), None);
    }

    #[test]
    fn watching_from_an_empty_account_works() {
        let probe = ArrivalProbe::new(0, 100);

        assert_eq!(probe.credited(0), None);
        assert_eq!(probe.credited(100), Some(100));
    }
}
