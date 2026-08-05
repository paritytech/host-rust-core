//! Unload tokens and the unload fee, as the chain reports them.
//!
//! [`crate::host_logic::coinage::unload_token`] decides *which* tokens an unload
//! should present; this module supplies the two facts that decision needs from
//! the chain — which free slots are already spent, and whether the fee account
//! can cover the fee — and turns a chosen grant into the extension that carries
//! it.
//!
//! # A free token is a slot, named by an alias
//!
//! A free token is one `(period, counter)` pair. The chain does not record the
//! pair: it records the *alias* the user's personhood key produces in that pair's
//! signing context, which is what keeps one user's spending from being linkable
//! to another's. So probing whether a slot is free means deriving its alias
//! locally and asking whether the chain has seen it.
//!
//! Slots are probed for the current period first and then, inside the lookback
//! grace window, for the previous one. That window exists because a period can
//! roll over between planning a transaction and the runtime validating it, and a
//! token from the period that just ended is still honoured for a while.
//!
//! # A paid token is a whole key, not a slot in one
//!
//! The paid ring's collection is `"coinage/paidtkn!" ‖ period_le`, one per period,
//! and its proof context carries the period and no counter. So a paid member key
//! is worth exactly one token per period — where a free personhood key covers the
//! period's whole allowance. The wallet therefore keeps a *series* of paid keys per
//! period, derived at `//coinage//paidtkn//<period>//<slot>`, and each one has to
//! be joined and paid for separately.
//!
//! [`read_paid_ring_state`] reports each slot's three independent facts: whether
//! its key is registered (`PaidUnloadTokenMembers`), whether the members pallet has
//! placed it in a provable ring, and whether its one token has already been spent
//! (`PaidUnloadTokenConsumed`). Registered-and-in-a-ring-and-unspent is a token in
//! hand; unregistered is a token the wallet can buy; spent is dead until the period
//! rolls over, because the pallet refuses a member key it has already seen.
//!
//! Whether a join can be *afforded* is not readable at all. The pallet prices it as
//! `WeightToFee(coin_lifecycle_weight())`, which is neither a published constant nor
//! exposed by a runtime API, so this module does not guess: it reports
//! `can_fund_join: false` and leaves the judgement to the caller through
//! [`PaidRingState::with_fundable_joins`].

use core::time::Duration;

use subxt::ext::scale_value::scale::decode_as_type;
use subxt::ext::scale_value::{Composite, Value, ValueDef};
use verifiable::GenerateVerifiable;
use verifiable::ring::bandersnatch::BandersnatchVrfVerifiable;

use crate::host_logic::coinage::chain_constants::CoinageChainConstants;
use crate::host_logic::coinage::derivation;
use crate::host_logic::coinage::error::CoinageError;
use crate::host_logic::coinage::params::CoinageParameters;
use crate::host_logic::coinage::types::{CoinAccountId, Timestamp};
use crate::host_logic::coinage::unload_token::{FreeTokenAvailability, PaidRingState, PaidSlot};
use crate::runtime::coinage::extension::{free_token_signing_context, paid_token_signing_context};
use crate::runtime::coinage::{ring, storage};
use crate::runtime::statement_allowance::extension::Metadata;
use crate::runtime::statement_allowance::rpc::RpcClient;

/// The alias the personhood key produces for one free-token slot.
///
/// The same value the token's proof will yield, which is what lets the layer
/// check a slot without doing ring-VRF work.
pub fn free_token_alias(
    personhood_entropy: [u8; 32],
    period: u32,
    counter: u32,
) -> Result<[u8; 32], CoinageError> {
    let secret = BandersnatchVrfVerifiable::new_secret(personhood_entropy);
    let context = free_token_signing_context(period, counter);
    let alias =
        BandersnatchVrfVerifiable::alias_in_context(&secret, &context).map_err(|error| {
            CoinageError::Internal(format!("free-token alias derivation failed: {error:?}"))
        })?;

    alias
        .as_ref()
        .try_into()
        .map_err(|_| CoinageError::Internal("free-token alias is not 32 bytes".to_string()))
}

/// The periods whose free tokens are still worth probing, most preferred first.
///
/// The current period always leads. The previous one follows only while `now` is
/// still inside the grace window after the boundary.
pub fn eligible_periods(
    now: Timestamp,
    period_length: Duration,
    grace: Duration,
) -> Result<Vec<u32>, CoinageError> {
    let length = period_length.as_millis();
    if length == 0 {
        return Err(CoinageError::Internal(
            "the runtime reports a zero-length unload-token period".to_string(),
        ));
    }

    let current = u32::try_from(u128::from(now.0) / length)
        .map_err(|_| CoinageError::Internal("the unload-token period overflows u32".to_string()))?;
    let elapsed_in_period = u128::from(now.0) % length;

    let mut periods = vec![current];
    if current > 0 && elapsed_in_period < grace.as_millis() {
        periods.push(current - 1);
    }
    Ok(periods)
}

/// Read which free-token slots the chain reports consumed, pinned to `at`.
///
/// Probes the same window resolution will consider: every counter in the layer's
/// search range, bounded by the runtime's per-period allowance, across every
/// eligible period. Probing a wider window would only find slots the runtime
/// refuses.
pub async fn read_free_token_availability(
    rpc: &RpcClient,
    personhood_entropy: [u8; 32],
    now: Timestamp,
    params: &CoinageParameters,
    constants: &CoinageChainConstants,
    at: &str,
) -> Result<FreeTokenAvailability, CoinageError> {
    let periods = eligible_periods(
        now,
        constants.unload_token_period,
        params.period_lookback_grace,
    )?;
    let search_range = params
        .free_token_counter_search_range
        .min(constants.max_free_unload_tokens_per_period);

    let mut availability = FreeTokenAvailability::fresh(periods.clone());
    for period in periods {
        for counter in 0..search_range {
            let alias = free_token_alias(personhood_entropy, period, counter)?;
            let consumed = read(
                rpc,
                &storage::consumed_free_unload_tokens_key(period, &alias),
                at,
            )
            .await?
            .is_some();
            if consumed {
                availability.consumed.insert((period, counter));
            }
        }
    }

    Ok(availability)
}

/// The paid-token period `now` falls in.
///
/// Uses the *paid* period length, which is a different constant from the free
/// one — three days against one on the reference runtime. Mixing them names a
/// period whose collection the wallet is not proving against.
pub fn paid_period(now: Timestamp, constants: &CoinageChainConstants) -> Result<u32, CoinageError> {
    Ok(
        *eligible_periods(now, constants.paid_unload_token_period, Duration::ZERO)?
            .first()
            .expect("eligible_periods always yields the current period; qed"),
    )
}

/// When the chain stops honouring `period`'s paid tokens.
///
/// `(period + 1) * paid_period + ring_expiration`, matching the pallet's
/// `period_expiration_time`. A token proved past this is refused as stale, so a
/// join placed near the boundary buys very little.
pub fn paid_period_expiry(
    period: u32,
    constants: &CoinageChainConstants,
) -> Result<Timestamp, CoinageError> {
    let length = constants.paid_unload_token_period.as_millis();
    let end = u128::from(period)
        .checked_add(1)
        .and_then(|next| next.checked_mul(length))
        .and_then(|end| end.checked_add(constants.paid_unload_token_ring_expiration.as_millis()))
        .and_then(|end| u64::try_from(end).ok())
        .ok_or_else(|| {
            CoinageError::Internal("a paid-token period expiry overflows".to_string())
        })?;

    Ok(Timestamp(end))
}

/// The alias one paid-token slot's key produces for its period.
///
/// The context carries the period and nothing else, which is why one key is one
/// token: there is no counter to vary.
pub fn paid_token_alias(entropy: &[u8], period: u32, slot: u32) -> Result<[u8; 32], CoinageError> {
    let vrf_entropy = derivation::paid_token_ring_vrf_entropy(entropy, period, slot)?;
    let secret = BandersnatchVrfVerifiable::new_secret(vrf_entropy);
    let context = paid_token_signing_context(period);
    let alias =
        BandersnatchVrfVerifiable::alias_in_context(&secret, &context).map_err(|error| {
            CoinageError::Internal(format!("paid-token alias derivation failed: {error:?}"))
        })?;

    alias
        .as_ref()
        .try_into()
        .map_err(|_| CoinageError::Internal("paid-token alias is not 32 bytes".to_string()))
}

/// Read what the chain says about the paid unload-token ring, pinned to `at`.
///
/// Reports each slot's registration, onboarding and consumption, plus whether the
/// period's collection exists at all.
///
/// A slot's consumption is checked against the ring its key actually sits in,
/// since `PaidUnloadTokenConsumed` is keyed by ring index. A registered key whose
/// onboarding has not completed has no ring yet, and its token is therefore
/// unspent and unprovable at the same time. That is reported as `joined` without
/// `onboarded` rather than as an error, because waiting is the correct response.
///
/// The returned state reports `can_fund_join: false`. Whether a join is affordable
/// is not a storage read — the pallet prices it from a weight — so the caller
/// decides and applies [`PaidRingState::with_fundable_joins`].
pub async fn read_paid_ring_state(
    rpc: &RpcClient,
    metadata: &Metadata,
    entropy: &[u8],
    now: Timestamp,
    params: &CoinageParameters,
    constants: &CoinageChainConstants,
    at: &str,
) -> Result<PaidRingState, CoinageError> {
    let period = paid_period(now, constants)?;
    let collection = storage::paid_token_collection_id(period);
    let collection_exists = read(
        rpc,
        &storage::paid_token_collections_created_key(period),
        at,
    )
    .await?
    .is_some();

    let mut slots = Vec::with_capacity(params.paid_token_slot_search_range as usize);
    for slot in 0..params.paid_token_slot_search_range {
        let key = derivation::paid_token_member_key(entropy, period, slot)?;
        let joined = read(rpc, &storage::paid_unload_token_members_key(&key), at)
            .await?
            .is_some();

        // Only a registered key can be in a ring, and finding out costs a ring
        // lookup — so an unregistered slot short-circuits.
        let (onboarded, spent) = if joined {
            match ring::find_ring_including(rpc, metadata, &collection, &key, at).await? {
                Some(ring) => {
                    let alias = paid_token_alias(entropy, period, slot)?;
                    let spent = read(
                        rpc,
                        &storage::paid_unload_token_consumed_key(
                            period,
                            ring.location.index,
                            &alias,
                        ),
                        at,
                    )
                    .await?
                    .is_some();
                    (true, spent)
                }
                // Registered but not in a ring yet, so nothing can have consumed
                // its alias and nothing can prove it either.
                None => (false, false),
            }
        } else {
            (false, false)
        };

        slots.push(PaidSlot {
            slot,
            joined,
            onboarded,
            spent,
        });
    }

    Ok(PaidRingState {
        period,
        collection_exists,
        can_fund_join: false,
        slots,
    })
}

/// The fee account's free native balance, pinned to `at`.
///
/// An account the chain has never seen has no entry, which reads as a zero
/// balance rather than an error: a fee account nobody has funded is an ordinary
/// state, and it means the unload takes its fee from the output instead.
pub async fn read_fee_account_balance(
    rpc: &RpcClient,
    metadata: &Metadata,
    account: CoinAccountId,
    at: &str,
) -> Result<u128, CoinageError> {
    let Some(raw) = read(rpc, &storage::system_account_key(&account), at).await? else {
        return Ok(0);
    };
    let type_id = metadata
        .storage_value_type("System", "Account")
        .ok_or_else(|| {
            CoinageError::Internal("System.Account is absent from metadata".to_string())
        })?;
    let value = decode_as_type(&mut &raw[..], type_id, metadata.registry()).map_err(|error| {
        CoinageError::Internal(format!("decoding the fee account failed: {error}"))
    })?;

    free_balance(&value).ok_or_else(|| {
        CoinageError::Internal("the fee account carried no free balance".to_string())
    })
}

/// Pull `data.free` out of a decoded `AccountInfo`.
fn free_balance(value: &Value<u32>) -> Option<u128> {
    let ValueDef::Composite(Composite::Named(fields)) = &value.value else {
        return None;
    };
    let data = fields
        .iter()
        .find(|(name, _)| name == "data")
        .map(|(_, value)| value)?;
    let ValueDef::Composite(Composite::Named(balances)) = &data.value else {
        return None;
    };
    balances
        .iter()
        .find(|(name, _)| name == "free")
        .and_then(|(_, value)| value.as_u128())
}

/// One pinned storage read.
async fn read(rpc: &RpcClient, key: &[u8], at: &str) -> Result<Option<Vec<u8>>, CoinageError> {
    rpc.get_storage_at(key, at)
        .await
        .map_err(|error| CoinageError::SubscriptionError(error.to_string()))
}

#[cfg(test)]
mod tests {
    use parity_scale_codec::Encode;
    use subxt_rpcs::RpcClient as HostRpcClient;

    use crate::host_logic::coinage::chain_constants::next_people_paseo;
    use crate::host_logic::coinage::unload_token::{TokenGrant, resolve};
    use crate::runtime::statement_allowance::rpc::testing::ScriptedRpc;

    use super::*;

    const FIXTURE: &[u8] = include_bytes!("../../../tests/fixtures/paseo-next-v2-metadata.scale");

    const ENTROPY: [u8; 32] = [3; 32];

    fn metadata() -> Metadata {
        Metadata::decode(FIXTURE).expect("the fixture decodes")
    }

    fn block_on<F: core::future::Future>(future: F) -> F::Output {
        futures::executor::block_on(future)
    }

    fn scripted(responses: &[String]) -> (ScriptedRpc, RpcClient) {
        let scripted = ScriptedRpc::new(responses.iter().map(String::as_str));
        let rpc = RpcClient::new(HostRpcClient::new(scripted.clone()));
        (scripted, rpc)
    }

    /// A `()` storage value: the marker a consumed slot leaves behind.
    fn present() -> String {
        "\"0x\"".to_string()
    }

    const ABSENT: &str = "null";

    fn params() -> CoinageParameters {
        CoinageParameters {
            free_token_counter_search_range: 3,
            paid_token_slot_search_range: 2,
            ..CoinageParameters::default()
        }
    }

    /// The middle of `period`, which is past the lookback grace window and so
    /// probes one period rather than two.
    fn mid_period(constants: &CoinageChainConstants, period: u64) -> Timestamp {
        let length = constants.unload_token_period.as_millis() as u64;
        Timestamp(length * period + length / 2)
    }

    #[test]
    fn a_slot_alias_is_bound_to_its_period_and_counter() {
        // A token replayable across slots would let one allowance be spent
        // repeatedly, so every pair must produce its own alias.
        let first = free_token_alias(ENTROPY, 10, 0).expect("derives");
        let same = free_token_alias(ENTROPY, 10, 0).expect("derives");
        let other_counter = free_token_alias(ENTROPY, 10, 1).expect("derives");
        let other_period = free_token_alias(ENTROPY, 11, 0).expect("derives");
        let other_user = free_token_alias([9; 32], 10, 0).expect("derives");

        assert_eq!(first, same, "the same slot is the same alias");
        assert_ne!(first, other_counter);
        assert_ne!(first, other_period);
        assert_ne!(first, other_user, "aliases do not collide across wallets");
    }

    #[test]
    fn the_previous_period_stays_eligible_only_inside_the_grace_window() {
        let length = Duration::from_secs(1_000);
        let grace = Duration::from_secs(100);

        // 50 seconds into period 5: the boundary is close enough behind us that a
        // token minted for period 4 may still be honoured.
        let just_after = Timestamp(5_050_000);
        assert_eq!(
            eligible_periods(just_after, length, grace).expect("computes"),
            vec![5, 4]
        );

        // Half way through: only the current period.
        let settled = Timestamp(5_500_000);
        assert_eq!(
            eligible_periods(settled, length, grace).expect("computes"),
            vec![5]
        );

        // Inside the first period ever, there is no previous one to fall back to.
        assert_eq!(
            eligible_periods(Timestamp(10), length, grace).expect("computes"),
            vec![0]
        );
    }

    #[test]
    fn a_zero_length_period_is_refused() {
        let refused = eligible_periods(Timestamp(1), Duration::ZERO, Duration::ZERO)
            .expect_err("a zero-length period has no slot arithmetic");

        assert!(refused.to_string().contains("zero-length"));
    }

    #[test]
    fn consumed_slots_are_read_back_as_consumed() {
        // Three counters, of which the middle one is spent.
        let (_scripted, rpc) = scripted(&[ABSENT.to_string(), present(), ABSENT.to_string()]);
        let constants = next_people_paseo();
        // Mid-period, past the one-hour grace window, so only the current
        // period is probed.
        let now = mid_period(&constants, 3);

        let availability = block_on(read_free_token_availability(
            &rpc,
            ENTROPY,
            now,
            &params(),
            &constants,
            "0xfeed",
        ))
        .expect("reads");

        assert_eq!(availability.eligible_periods, vec![3]);
        assert!(availability.is_free(3, 0));
        assert!(!availability.is_free(3, 1), "the chain saw this alias");
        assert!(availability.is_free(3, 2));
    }

    #[test]
    fn the_probe_window_never_exceeds_the_runtimes_allowance() {
        // The layer's search range is a policy knob; the runtime's per-period cap
        // is a fact. Probing past it would read slots the runtime refuses, and
        // each read costs a round trip.
        let constants = CoinageChainConstants {
            max_free_unload_tokens_per_period: 2,
            ..next_people_paseo()
        };
        let generous = CoinageParameters {
            free_token_counter_search_range: 50,
            ..CoinageParameters::default()
        };
        let (scripted, rpc) = scripted(&[ABSENT.to_string(), ABSENT.to_string()]);
        let now = mid_period(&constants, 1);

        block_on(read_free_token_availability(
            &rpc, ENTROPY, now, &generous, &constants, "0xfeed",
        ))
        .expect("reads");

        assert_eq!(scripted.calls().len(), 2, "one read per allowed counter");
    }

    #[test]
    fn an_availability_snapshot_drives_resolution() {
        // The whole point of the read: the first free slot resolution picks must
        // be one the chain has not already seen.
        let (_scripted, rpc) = scripted(&[present(), ABSENT.to_string(), ABSENT.to_string()]);
        let constants = next_people_paseo();
        let now = mid_period(&constants, 2);

        let availability = block_on(read_free_token_availability(
            &rpc,
            ENTROPY,
            now,
            &params(),
            &constants,
            "0xfeed",
        ))
        .expect("reads");
        let plan = resolve(
            1,
            &availability,
            &PaidRingState::unavailable(2),
            &params(),
            &constants,
        )
        .expect("a free slot remains");

        assert_eq!(
            plan.grants,
            vec![TokenGrant::Free {
                period: 2,
                counter: 1
            }],
            "counter 0 is spent, so the next one is taken"
        );
    }

    #[test]
    fn the_paid_period_is_measured_with_the_paid_period_length() {
        // The two period lengths are different constants — one day free, three
        // days paid on the reference runtime — and the paid one names the
        // collection a token proves against. Measuring with the free length picks
        // a period whose ring the wallet is not a member of, after paying to join.
        let constants = next_people_paseo();
        let day = constants.unload_token_period.as_millis() as u64;

        // Four days in: free period 4, paid period 1.
        let now = Timestamp(4 * day + day / 2);

        assert_eq!(
            eligible_periods(now, constants.unload_token_period, Duration::ZERO).expect("computes"),
            vec![4]
        );
        assert_eq!(paid_period(now, &constants).expect("computes"), 1);
    }

    #[test]
    fn a_paid_period_expires_after_its_end_plus_the_ring_expiration() {
        let constants = next_people_paseo();
        let period_ms = constants.paid_unload_token_period.as_millis() as u64;
        let expiration_ms = constants.paid_unload_token_ring_expiration.as_millis() as u64;

        // Period 2 ends when period 3 begins, and the ring lingers past that.
        assert_eq!(
            paid_period_expiry(2, &constants).expect("computes"),
            Timestamp(3 * period_ms + expiration_ms)
        );
    }

    #[test]
    fn a_slot_alias_is_bound_to_its_period_and_slot() {
        // Each slot must produce its own alias, or two slots would be one token.
        let first = paid_token_alias(&ENTROPY, 10, 0).expect("derives");
        let same = paid_token_alias(&ENTROPY, 10, 0).expect("derives");
        let other_slot = paid_token_alias(&ENTROPY, 10, 1).expect("derives");
        let other_period = paid_token_alias(&ENTROPY, 11, 0).expect("derives");
        let other_wallet = paid_token_alias(&[9u8; 32], 10, 0).expect("derives");

        assert_eq!(first, same, "the same slot is the same alias");
        assert_ne!(first, other_slot, "two slots are two tokens");
        assert_ne!(first, other_period);
        assert_ne!(first, other_wallet);

        // And a paid alias is not a free alias for the same period, because the
        // key and the context both differ.
        assert_ne!(first, free_token_alias(ENTROPY, 10, 0).expect("derives"));
    }

    #[test]
    fn an_unjoined_wallet_reports_every_slot_as_joinable_but_holds_no_token() {
        // One read for the collection, then one membership read per slot. Nothing
        // is joined, so no ring lookup happens.
        let (scripted, rpc) =
            scripted(&[ABSENT.to_string(), ABSENT.to_string(), ABSENT.to_string()]);
        let constants = next_people_paseo();
        let now = Timestamp(constants.paid_unload_token_period.as_millis() as u64 * 3);

        let state = block_on(read_paid_ring_state(
            &rpc,
            &metadata(),
            &ENTROPY,
            now,
            &params(),
            &constants,
            "0xfeed",
        ))
        .expect("reads");

        assert_eq!(state.period, 3);
        assert!(!state.collection_exists);
        assert_eq!(state.slots.len(), 2);
        assert!(state.slots.iter().all(|slot| slot.is_joinable()));
        assert!(
            !state.slots.iter().any(|slot| slot.is_ready()),
            "joinable is not the same as held"
        );
        assert_eq!(
            scripted.calls().len(),
            3,
            "an unjoined slot costs no ring lookup"
        );

        // A wallet out of free slots that cannot fund a join is told it has no
        // token, rather than handed a grant it cannot present.
        let exhausted = FreeTokenAvailability {
            eligible_periods: vec![state.period],
            consumed: (0..3).map(|counter| (state.period, counter)).collect(),
        };
        assert_eq!(
            resolve(1, &exhausted, &state, &params(), &constants),
            Err(CoinageError::NoUnloadToken)
        );
    }

    #[test]
    fn a_joined_slot_awaiting_onboarding_is_unspent_and_not_yet_ready() {
        // Joined, but the members pallet has not placed the key in a ring yet, so
        // there is no ring index to check consumption against. The honest answer
        // is "not spent" — and the slot is still not usable, because a proof needs
        // a ring. Waiting is the caller's move, not failing.
        let (_scripted, rpc) = scripted(&[
            present(),          // the period's collection exists
            present(),          // slot 0 is a member
            ABSENT.to_string(), // CurrentRingIndex: defaults to ring 0
            ABSENT.to_string(), // ring 0 has no root, so no ring holds the key
            ABSENT.to_string(), // slot 1 is not a member
        ]);
        let constants = next_people_paseo();
        let now = Timestamp(constants.paid_unload_token_period.as_millis() as u64);

        let state = block_on(read_paid_ring_state(
            &rpc,
            &metadata(),
            &ENTROPY,
            now,
            &params(),
            &constants,
            "0xfeed",
        ))
        .expect("reads");

        assert!(state.collection_exists);
        assert!(state.slots[0].joined);
        assert!(!state.slots[0].spent);
        assert!(
            !state.slots[0].is_ready(),
            "a key with no ring cannot be proved"
        );
        assert!(
            !state.slots[0].is_joinable(),
            "and it must not be joined twice; the pallet refuses a known key"
        );
    }

    /// `AccountInfo { nonce, consumers, providers, sufficients, data: AccountData
    /// { free, reserved, frozen, flags } }`.
    fn account_info(free: u128) -> Vec<u8> {
        let mut encoded = 7u32.encode(); // nonce
        encoded.extend(0u32.encode()); // consumers
        encoded.extend(1u32.encode()); // providers
        encoded.extend(0u32.encode()); // sufficients
        encoded.extend(free.encode());
        encoded.extend(0u128.encode()); // reserved
        encoded.extend(0u128.encode()); // frozen
        encoded.extend(0u128.encode()); // flags
        encoded
    }

    #[test]
    fn the_fee_account_balance_is_read_from_its_free_field() {
        let (_scripted, rpc) = scripted(&[format!(
            "\"0x{}\"",
            hex::encode(account_info(12_345_678_901))
        )]);

        let balance = block_on(read_fee_account_balance(
            &rpc,
            &metadata(),
            CoinAccountId([4; 32]),
            "0xfeed",
        ))
        .expect("reads");

        assert_eq!(balance, 12_345_678_901);
    }

    #[test]
    fn an_unfunded_fee_account_reads_as_zero_not_as_an_error() {
        // The account exists only once someone sends it money, and an unfunded
        // fee account is an ordinary state that selects the from-output fee mode.
        let (_scripted, rpc) = scripted(&[ABSENT.to_string()]);

        let balance = block_on(read_fee_account_balance(
            &rpc,
            &metadata(),
            CoinAccountId([4; 32]),
            "0xfeed",
        ))
        .expect("reads");

        assert_eq!(balance, 0);
    }
}
