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
//! # The paid ring is not implemented
//!
//! §6.5's fallback to paid tokens needs the membership collection identifier the
//! pallet derives per period, and that value is neither in metadata nor derivable
//! from anything this layer can see. [`read_paid_ring_state`] therefore reports
//! membership honestly — the one thing that *is* readable — and never claims the
//! ring can be joined, so resolution fails with `NoUnloadToken` rather than
//! building a token it cannot prove. Tracked as a known gap.

use core::time::Duration;

use subxt::ext::scale_value::scale::decode_as_type;
use subxt::ext::scale_value::{Composite, Value, ValueDef};
use verifiable::GenerateVerifiable;
use verifiable::ring::bandersnatch::BandersnatchVrfVerifiable;

use crate::host_logic::coinage::chain_constants::CoinageChainConstants;
use crate::host_logic::coinage::error::CoinageError;
use crate::host_logic::coinage::params::CoinageParameters;
use crate::host_logic::coinage::types::{CoinAccountId, Timestamp};
use crate::host_logic::coinage::unload_token::{FreeTokenAvailability, PaidRingState};
use crate::runtime::coinage::extension::free_token_signing_context;
use crate::runtime::coinage::storage;
use crate::runtime::statement_allowance::extension::Metadata;
use crate::runtime::statement_allowance::proof::member_key;
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

/// Read what the chain says about the paid unload-token ring, pinned to `at`.
///
/// `can_fund_join` is always false: see the module documentation. Membership is
/// read rather than assumed, so a wallet that already joined out of band is not
/// told it has no tokens.
pub async fn read_paid_ring_state(
    rpc: &RpcClient,
    personhood_entropy: [u8; 32],
    now: Timestamp,
    constants: &CoinageChainConstants,
    at: &str,
) -> Result<PaidRingState, CoinageError> {
    let period = *eligible_periods(now, constants.unload_token_period, Duration::ZERO)?
        .first()
        .expect("eligible_periods always yields the current period; qed");
    let is_member = read(
        rpc,
        &storage::paid_unload_token_members_key(&member_key(personhood_entropy)),
        at,
    )
    .await?
    .is_some();

    Ok(PaidRingState {
        period,
        is_member,
        can_fund_join: false,
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
            &PaidRingState {
                period: 2,
                is_member: false,
                can_fund_join: false,
            },
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
    fn the_paid_ring_is_never_reported_as_joinable() {
        // Claiming otherwise would produce a token this layer cannot prove.
        let (_scripted, rpc) = scripted(&[ABSENT.to_string()]);
        let constants = next_people_paseo();

        let state = block_on(read_paid_ring_state(
            &rpc,
            ENTROPY,
            Timestamp(constants.unload_token_period.as_millis() as u64),
            &constants,
            "0xfeed",
        ))
        .expect("reads");

        assert!(!state.is_member);
        assert!(
            !state.can_fund_join,
            "the paid ring's collection identifier is not derivable here"
        );

        // And so a wallet out of free slots is told it has no token at all,
        // rather than being handed a grant that cannot be built.
        let exhausted = FreeTokenAvailability {
            eligible_periods: vec![state.period],
            consumed: (0..3).map(|counter| (state.period, counter)).collect(),
        };
        assert_eq!(
            resolve(1, &exhausted, &state, &params(), &constants),
            Err(CoinageError::NoUnloadToken)
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
