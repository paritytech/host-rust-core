//! End-to-end scenarios over the coinage base layer.
//!
//! The unit tests inside each module check one thing at a time. This suite
//! drives the whole pipeline the way a host will — derive accounts, observe
//! chain state, select, plan tokens, build the extrinsic, submit, reconcile —
//! and asserts the invariants that only show up once the pieces are composed.
//!
//! There is no platform here because the base layer needs none: it is pure, and
//! chain facts arrive as observations. `ScriptedChain` stands in for the chain,
//! holding the state a real node would report so a scenario can advance it
//! deliberately.

use std::collections::{BTreeMap, BTreeSet};
use std::time::Duration;

use parity_scale_codec::{Decode, Encode};

use truapi_server::coinage::call::{CoinOutput, UnloadRecyclerIntoCoinsArgs};
use truapi_server::coinage::extension::{AsCoinageInfo, FreeTokenRing};
use truapi_server::host_logic::coinage::chain_constants::{
    CoinageChainConstants, next_people_paseo,
};
use truapi_server::host_logic::coinage::coin::CoinState;
use truapi_server::host_logic::coinage::derivation;
use truapi_server::host_logic::coinage::entry::EntryLocalState;
use truapi_server::host_logic::coinage::error::CoinageError;
use truapi_server::host_logic::coinage::event::LayerEvent;
use truapi_server::host_logic::coinage::operation::{OperationReceipt, OperationStatus};
use truapi_server::host_logic::coinage::params::CoinageParameters;
use truapi_server::host_logic::coinage::selection::{
    OutputRequirement, SelectionRequest, SelectionTier,
};
use truapi_server::host_logic::coinage::store::CoinageStore;
use truapi_server::host_logic::coinage::types::{
    Amount, CoinAccountId, CoinAge, CoinIndex, DenominationExponent, EntryIndex, ExtrinsicHash,
    OperationKind, PurseId, RevisionIndex, RingIndex, RingLocation, Timestamp,
};
use truapi_server::host_logic::coinage::unload_token::{
    FeeMode, FreeTokenAvailability, PaidRingState, TokenGrant, choose_fee_mode, resolve,
};

const ENTROPY: [u8; 32] = [7; 32];
const HOUR: Duration = Duration::from_secs(60 * 60);
const DAY: Duration = Duration::from_secs(24 * 60 * 60);
const TOKEN_PERIOD: u32 = 19_000;

/// The chain state a scenario has arranged.
///
/// Deliberately dumb: it records what a node would report and nothing else, so
/// a test that passes cannot be passing because the fake agreed with the code
/// about something it should not know.
#[derive(Debug, Default)]
struct ScriptedChain {
    /// Coin accounts the chain reports populated, with their observed age.
    coins: BTreeMap<CoinAccountId, CoinAge>,
    /// Recycler entries by member key: where they sit and how full the ring is.
    rings: BTreeMap<[u8; 32], (RingLocation, u32)>,
    /// Free unload-token slots the chain reports consumed.
    consumed_tokens: BTreeSet<(u32, u32)>,
}

impl ScriptedChain {
    /// Place a recycler entry into a ring with the given member count.
    fn load_entry(&mut self, member_key: [u8; 32], ring: RingLocation, members: u32) {
        self.rings.insert(member_key, (ring, members));
    }

    /// Report a coin account as holding a coin.
    fn credit_coin(&mut self, account: CoinAccountId, age: CoinAge) {
        self.coins.insert(account, age);
    }

    fn ring_of(&self, member_key: &[u8; 32]) -> Option<(RingLocation, u32)> {
        self.rings.get(member_key).copied()
    }

    fn age_of(&self, account: &CoinAccountId) -> Option<CoinAge> {
        self.coins.get(account).copied()
    }

    fn free_tokens(&self) -> FreeTokenAvailability {
        FreeTokenAvailability {
            eligible_periods: vec![TOKEN_PERIOD],
            consumed: self.consumed_tokens.clone(),
        }
    }
}

fn exponent(value: i8) -> DenominationExponent {
    DenominationExponent::new(value).expect("exponent is in range")
}

fn ring(index: u32, revision: u32) -> RingLocation {
    RingLocation::new(RingIndex(index), RevisionIndex(revision))
}

fn params() -> CoinageParameters {
    CoinageParameters::default()
}

fn constants() -> CoinageChainConstants {
    next_people_paseo()
}

fn any(cents: u64) -> SelectionRequest {
    SelectionRequest {
        amount: Amount::from_cents(cents),
        outputs: OutputRequirement::AnyDenominations,
        allow_degraded: false,
    }
}

/// Allocate an entry locally and place it into a well-populated ring, the way a
/// top-up does.
fn top_up_entry(
    store: &mut CoinageStore,
    chain: &mut ScriptedChain,
    purse: PurseId,
    exponent_value: i8,
    now: Timestamp,
    jitter: Duration,
    ring_at: RingLocation,
) -> EntryIndex {
    let index = store
        .allocate_entry(purse, exponent(exponent_value), now, jitter)
        .expect("purse exists");
    let member_key =
        derivation::entry_member_key(&ENTROPY, purse, index).expect("derivation succeeds");
    chain.load_entry(member_key, ring_at, 32);
    index
}

/// Feed every locally known entry's ring state back into the store.
fn observe_entries(store: &mut CoinageStore, chain: &ScriptedChain, purse: PurseId) {
    for entry in store.entries_in(purse) {
        let member_key = derivation::entry_member_key(&ENTROPY, purse, entry.index)
            .expect("derivation succeeds");
        if let Some((ring_at, members)) = chain.ring_of(&member_key) {
            store
                .observe_entry_ring(purse, entry.index, ring_at, members, &params())
                .expect("entry exists");
        }
    }
}

#[test]
fn the_reference_runtime_is_accepted_before_anything_else_happens() {
    // A host validates constants once at connection. Everything downstream
    // assumes this passed.
    assert_eq!(constants().validate(), Ok(()));
    assert_eq!(constants().recycle_at_age(), CoinAge(14));
}

#[test]
fn a_topped_up_purse_becomes_spendable_only_after_its_jitter_elapses() {
    let mut store = CoinageStore::new("Main".to_string());
    let mut chain = ScriptedChain::default();
    let start = Timestamp(1_000_000);

    let index = top_up_entry(
        &mut store,
        &mut chain,
        PurseId::MAIN,
        4,
        start,
        HOUR,
        ring(1, 0),
    );
    observe_entries(&mut store, &chain, PurseId::MAIN);

    // The ring is full, but the entry is still inside its decorrelation delay,
    // so the value is real and not yet spendable.
    let held = store.balance(PurseId::MAIN, start).expect("purse exists");
    assert_eq!(held.spendable, Amount::ZERO);
    assert_eq!(held.pending, Amount::from_cents(16));

    let later = start.saturating_add(HOUR);
    let ready = store.balance(PurseId::MAIN, later).expect("purse exists");
    assert_eq!(ready.spendable, Amount::from_cents(16));
    assert_eq!(ready.spendable_strict, Amount::from_cents(16));
    assert_eq!(ready.pending, Amount::ZERO);

    assert_eq!(
        store.entry(PurseId::MAIN, index).expect("exists").local,
        EntryLocalState::Available
    );
}

#[test]
fn an_unload_runs_from_selection_through_to_a_submittable_extrinsic() {
    let mut store = CoinageStore::new("Main".to_string());
    let mut chain = ScriptedChain::default();
    let now = Timestamp(2_000_000);
    let purse = store.create_purse("Groceries".to_string());

    // Two 16-cent entries in the same ring: one group, one unload token.
    for _ in 0..2 {
        top_up_entry(
            &mut store,
            &mut chain,
            purse,
            4,
            now,
            Duration::ZERO,
            ring(3, 5),
        );
    }
    observe_entries(&mut store, &chain, purse);
    store.take_events();

    // -- select -----------------------------------------------------------
    let (handle, plan) = store
        .begin_operation(purse, OperationKind::Transfer, &any(20), &constants(), now)
        .expect("32 cents are ready");

    assert_eq!(plan.tier, SelectionTier::UnloadIntoCoins);
    assert_eq!(plan.target_value(), Amount::from_cents(20));
    assert_eq!(plan.unloads.len(), 1);
    assert_eq!(plan.unload_tokens_required(), 1);

    let group = &plan.unloads[0];
    assert_eq!(group.entries.len(), 2);
    assert_eq!(group.ring, ring(3, 5));
    // The group's own change absorbs what the request does not need.
    let produced: Amount = group
        .target_outputs
        .iter()
        .chain(group.change_outputs.iter())
        .map(|exponent| exponent.value())
        .sum();
    assert_eq!(produced, Amount::from_cents(32));

    // Selecting locked the entries, so the purse now reads as pending.
    let locked = store.balance(purse, now).expect("purse exists");
    assert_eq!(locked.spendable, Amount::ZERO);
    assert_eq!(locked.pending, Amount::from_cents(32));

    // -- plan tokens and fee ----------------------------------------------
    let token_plan = resolve(
        plan.unload_tokens_required(),
        &chain.free_tokens(),
        &PaidRingState {
            period: TOKEN_PERIOD,
            is_member: false,
            can_fund_join: true,
        },
        &params(),
        &constants(),
    )
    .expect("a free slot is available");

    assert_eq!(
        token_plan.grants,
        vec![TokenGrant::Free {
            period: TOKEN_PERIOD,
            counter: 0
        }]
    );
    assert!(!token_plan.join_paid_ring);

    let fee_mode = choose_fee_mode(1_000_000, 5_000);
    assert_eq!(fee_mode, FeeMode::Prepaid);

    // -- allocate destinations and build the call --------------------------
    let mut outputs = Vec::new();
    for output in group
        .target_outputs
        .iter()
        .chain(group.change_outputs.iter())
    {
        let index = store
            .add_pending_coin(purse, *output)
            .expect("purse exists");
        outputs.push(CoinOutput {
            exponent: *output,
            account: derivation::coin_account_id(&ENTROPY, purse, index)
                .expect("derivation succeeds"),
        });
    }

    let aliases: Vec<[u8; 32]> = group
        .entries
        .iter()
        .map(|entry| derivation::entry_member_key(&ENTROPY, purse, *entry).expect("derives"))
        .collect();

    let args = UnloadRecyclerIntoCoinsArgs::new(
        aliases.clone(),
        group.exponent,
        group.ring,
        &outputs,
        fee_mode.max_fee(5_000),
        &constants(),
    )
    .expect("the group balances");

    assert_eq!(args.value, 4);
    assert_eq!(args.index, 3);
    assert_eq!(args.revision, 5);
    assert_eq!(args.max_fee, 0, "prepaid unloads carry no fee ceiling");
    assert_eq!(args.split_into.output_count(), outputs.len());
    assert!(!args.encode().is_empty());

    // Every destination account is distinct: the purse's index space never
    // hands the same account out twice.
    let distinct: BTreeSet<CoinAccountId> = outputs.iter().map(|o| o.account).collect();
    assert_eq!(distinct.len(), outputs.len());

    // -- build the extension ----------------------------------------------
    let info = AsCoinageInfo::FreeUnloadToken {
        ring: FreeTokenRing::People,
        proof: truapi_server::coinage::call::RawEncoded(vec![0xAB; 96]),
        period: TOKEN_PERIOD,
        counter: 0,
        alias_proofs: aliases
            .iter()
            .map(|_| truapi_server::coinage::call::RawEncoded(vec![0xCD; 64]))
            .collect(),
    };
    assert_eq!(info.variant_name(), "AsUnloadTokenPeople");
    assert_eq!(info.alias_proofs().len(), 2);
    let extra = info.encode_extra_with_index(1);
    assert_eq!(&extra[..2], &[1u8, 1], "Some, then the variant index");

    // -- submit and settle -------------------------------------------------
    store
        .record_submission(handle, ExtrinsicHash([9; 32]))
        .expect("operation is open");
    assert_eq!(
        store.operation(handle).expect("still open").status,
        OperationStatus::Submitted
    );
    assert!(
        !store
            .operation(handle)
            .expect("still open")
            .status
            .is_cancellable(),
        "an in-flight operation cannot be cancelled"
    );

    let consumed = plan.lock_set(purse);
    store
        .finish_operation(handle, OperationReceipt::default(), &consumed)
        .expect("operation is open");

    for entry in group.entries.iter() {
        assert_eq!(
            store.entry(purse, *entry).expect("exists").local,
            EntryLocalState::Consumed,
            "unloaded entries retire so their indices are never reused"
        );
    }
    assert!(store.operation(handle).is_none());

    // -- observe the minted coins ------------------------------------------
    for coin in store.coins_in(purse) {
        let account = derivation::coin_account_id(&ENTROPY, purse, coin.index).expect("derives");
        chain.credit_coin(account, CoinAge(0));
        // Read the age back out of the chain rather than restating it, so the
        // observation path is driven by the fake and not by the assertion.
        let age = chain
            .age_of(&account)
            .expect("the chain reports the account");
        store
            .observe_coin(purse, coin.index, age)
            .expect("coin exists");
    }

    // Value is conserved end to end: 32 cents in, 32 cents out.
    let settled = store.balance(purse, now).expect("purse exists");
    assert_eq!(settled.spendable, Amount::from_cents(32));
    assert_eq!(settled.pending, Amount::ZERO);

    let events = store.take_events();
    assert!(
        events
            .iter()
            .any(|event| matches!(event, LayerEvent::EntryConsumed { .. }))
    );
    assert!(
        events
            .iter()
            .any(|event| matches!(event, LayerEvent::OperationCompleted { .. }))
    );
}

#[test]
fn a_purse_survives_persistence_and_resumes_its_in_flight_operation() {
    let mut store = CoinageStore::new("Main".to_string());
    let mut chain = ScriptedChain::default();
    let now = Timestamp(3_000_000);

    top_up_entry(
        &mut store,
        &mut chain,
        PurseId::MAIN,
        5,
        now,
        Duration::ZERO,
        ring(1, 1),
    );
    observe_entries(&mut store, &chain, PurseId::MAIN);

    let (handle, _) = store
        .begin_operation(
            PurseId::MAIN,
            OperationKind::ExternalOffload,
            &any(20),
            &constants(),
            now,
        )
        .expect("32 cents are ready");
    store
        .record_submission(handle, ExtrinsicHash([1; 32]))
        .expect("operation is open");

    // The host writes the store out and the process dies.
    let encoded = store.encode();
    let mut restored =
        CoinageStore::decode(&mut &encoded[..]).expect("the store round-trips through SCALE");

    // An operation that broadcast is handed back for reconciliation rather than
    // being failed: the chain may well have accepted it.
    let pending = restored.reconcile_after_restart();
    assert_eq!(pending, vec![handle]);
    assert_eq!(
        restored.operation(handle).expect("still open").submitted,
        vec![ExtrinsicHash([1; 32])]
    );
    assert_eq!(
        restored.take_events().last(),
        Some(&LayerEvent::Resynced),
        "Resynced closes reconstruction so later events read as live"
    );
}

#[test]
fn a_restart_while_preparing_releases_the_records_it_held() {
    let mut store = CoinageStore::new("Main".to_string());
    let mut chain = ScriptedChain::default();
    let now = Timestamp(4_000_000);

    let index = top_up_entry(
        &mut store,
        &mut chain,
        PurseId::MAIN,
        5,
        now,
        Duration::ZERO,
        ring(1, 1),
    );
    observe_entries(&mut store, &chain, PurseId::MAIN);

    let (handle, _) = store
        .begin_operation(
            PurseId::MAIN,
            OperationKind::Transfer,
            &any(32),
            &constants(),
            now,
        )
        .expect("32 cents are ready");

    // Nothing was broadcast, so pre-submission scratch state is worthless and
    // the restart is equivalent to a cancel.
    let pending = store.reconcile_after_restart();

    assert!(pending.is_empty());
    assert!(store.operation(handle).is_none());
    assert_eq!(
        store.entry(PurseId::MAIN, index).expect("exists").local,
        EntryLocalState::Available,
        "the entry is selectable again"
    );
    assert_eq!(
        store
            .balance(PurseId::MAIN, now)
            .expect("purse exists")
            .spendable,
        Amount::from_cents(32)
    );
}

#[test]
fn an_entry_approaching_ring_expiry_is_flagged_for_rescue() {
    // The failure this guards against is the only way value can vanish from a
    // wallet whose entropy and chain identity are intact: an entry whose ring
    // is cleaned up before it is ever unloaded. Recycling coins into entries
    // without unloading entries back out destroys funds silently.
    let mut store = CoinageStore::new("Main".to_string());
    let mut chain = ScriptedChain::default();
    let immutable_since = Timestamp(5_000_000);

    let index = top_up_entry(
        &mut store,
        &mut chain,
        PurseId::MAIN,
        4,
        immutable_since,
        Duration::ZERO,
        ring(2, 0),
    );
    observe_entries(&mut store, &chain, PurseId::MAIN);

    let expiration = constants().recycler_expiration_time;
    let margin = params().rescue_margin(expiration);
    let entry = *store.entry(PurseId::MAIN, index).expect("exists");

    let deadline = immutable_since.saturating_add(expiration);
    let trigger = deadline.saturating_sub(margin);

    assert!(
        !entry.needs_rescue(
            trigger.saturating_sub(DAY),
            immutable_since,
            expiration,
            margin
        ),
        "a day before the margin there is nothing to do"
    );
    assert!(
        entry.needs_rescue(trigger, immutable_since, expiration, margin),
        "at the margin the sweep must act"
    );
    // 90 days expiry, 25% margin: roughly 22 days of slack.
    assert!(margin >= DAY * 22);
}

#[test]
fn a_purse_cannot_be_closed_while_it_holds_records_for_an_operation() {
    let mut store = CoinageStore::new("Main".to_string());
    let mut chain = ScriptedChain::default();
    let now = Timestamp(6_000_000);
    let purse = store.create_purse("Groceries".to_string());

    top_up_entry(
        &mut store,
        &mut chain,
        purse,
        4,
        now,
        Duration::ZERO,
        ring(1, 0),
    );
    observe_entries(&mut store, &chain, purse);

    let (handle, _) = store
        .begin_operation(purse, OperationKind::Transfer, &any(16), &constants(), now)
        .expect("16 cents are ready");

    assert_eq!(
        store.close_purse(purse, PurseId::MAIN, Amount::ZERO),
        Err(CoinageError::PurseHasInFlightOperations)
    );

    store
        .fail_operation(handle, CoinageError::Cancelled)
        .expect("operation is open");
    store
        .close_purse(purse, PurseId::MAIN, Amount::from_cents(16))
        .expect("nothing is in flight now");

    // The identifier is not handed out again: it names a derivation namespace,
    // and reuse would let a new purse inherit the closed purse's history.
    let next = store.create_purse("Rent".to_string());
    assert_ne!(next, purse);
}

#[test]
fn waiting_on_a_ripening_entry_reads_differently_from_being_broke() {
    let mut store = CoinageStore::new("Main".to_string());
    let mut chain = ScriptedChain::default();
    let now = Timestamp(7_000_000);

    top_up_entry(
        &mut store,
        &mut chain,
        PurseId::MAIN,
        4,
        now,
        HOUR,
        ring(1, 0),
    );
    observe_entries(&mut store, &chain, PurseId::MAIN);

    // The value exists but is still ripening, so the caller is told to retry.
    assert!(matches!(
        store.begin_operation(
            PurseId::MAIN,
            OperationKind::Transfer,
            &any(16),
            &constants(),
            now
        ),
        Err(CoinageError::NoReadyEntries { .. })
    ));

    // Ask for more than the purse will ever hold and it is a dead end instead.
    assert!(matches!(
        store.begin_operation(
            PurseId::MAIN,
            OperationKind::Transfer,
            &any(4_096),
            &constants(),
            now
        ),
        Err(CoinageError::InsufficientFunds { .. })
    ));
}

#[test]
fn a_degraded_ring_is_refused_unless_the_caller_accepts_weaker_anonymity() {
    let mut store = CoinageStore::new("Main".to_string());
    let mut chain = ScriptedChain::default();
    let now = Timestamp(8_000_000);

    let index = store
        .allocate_entry(PurseId::MAIN, exponent(4), now, Duration::ZERO)
        .expect("purse exists");
    let member_key = derivation::entry_member_key(&ENTROPY, PurseId::MAIN, index).expect("derives");
    // Three members is well below the anonymity floor of ten.
    chain.load_entry(member_key, ring(1, 0), 3);
    observe_entries(&mut store, &chain, PurseId::MAIN);

    let balance = store.balance(PurseId::MAIN, now).expect("purse exists");
    assert_eq!(balance.spendable, Amount::from_cents(16));
    assert_eq!(
        balance.spendable_strict,
        Amount::ZERO,
        "the strict figure excludes value sitting in a thin ring"
    );

    let strict = SelectionRequest {
        allow_degraded: false,
        ..any(16)
    };
    assert!(matches!(
        store.begin_operation(
            PurseId::MAIN,
            OperationKind::Transfer,
            &strict,
            &constants(),
            now
        ),
        Err(CoinageError::NoReadyEntries { .. })
    ));

    let permissive = SelectionRequest {
        allow_degraded: true,
        ..any(16)
    };
    let (_, plan) = store
        .begin_operation(
            PurseId::MAIN,
            OperationKind::Transfer,
            &permissive,
            &constants(),
            now,
        )
        .expect("degraded entries are allowed here");
    assert_eq!(plan.tier, SelectionTier::UnloadIntoCoins);
}

#[test]
fn an_aging_coin_is_offered_for_recycling_before_the_chain_rejects_it() {
    let mut store = CoinageStore::new("Main".to_string());

    let young = store
        .add_pending_coin(PurseId::MAIN, exponent(4))
        .expect("purse exists");
    let old = store
        .add_pending_coin(PurseId::MAIN, exponent(4))
        .expect("purse exists");
    store
        .observe_coin(PurseId::MAIN, young, CoinAge(2))
        .expect("coin exists");
    store
        .observe_coin(PurseId::MAIN, old, CoinAge(14))
        .expect("coin exists");

    let due = store.coins_needing_recycling(PurseId::MAIN, constants().recycle_at_age());

    assert_eq!(due, vec![old]);
    // Two transfers of headroom remain below the chain's cap of 16.
    let record = store.coin(PurseId::MAIN, old).expect("exists");
    assert!(record.is_usable(constants().maximum_age));
    assert_eq!(record.state, CoinState::Available);
}

#[test]
fn indices_are_never_reused_across_a_purse_lifetime() {
    let mut store = CoinageStore::new("Main".to_string());
    let purse = store.create_purse("Groceries".to_string());
    let mut seen = BTreeSet::new();

    for _ in 0..8 {
        let index = store
            .add_pending_coin(purse, exponent(2))
            .expect("purse exists");
        assert!(seen.insert(index), "coin index handed out twice");

        let account = derivation::coin_account_id(&ENTROPY, purse, index).expect("derives");
        // Distinct indices must yield distinct accounts, or the no-reuse
        // invariant buys nothing.
        assert_ne!(
            account,
            derivation::coin_account_id(&ENTROPY, purse, CoinIndex(999)).expect("derives")
        );
    }

    assert_eq!(
        store.purse(purse).expect("exists").next_coin_index,
        CoinIndex(8)
    );
}
