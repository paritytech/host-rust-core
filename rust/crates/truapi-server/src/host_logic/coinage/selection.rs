//! Coin and recycler-entry selection.
//!
//! Selection answers one question: which records should an operation consume to
//! produce a requested amount inside coinage? Three strategies are tried in
//! priority order — exact match, split, unload-into-coins — and the first that
//! succeeds wins.
//!
//! Ordering is fixed before any strategy runs, so two conformant
//! implementations with the same purse contents choose the same records. That
//! determinism is a conformance requirement, not an optimization: it is what
//! lets an implementation be swapped without changing on-chain behaviour.
//!
//! Selection is pure. It reads a snapshot of the purse's records and returns a
//! plan; locking, signing, and submission belong to the caller.

use std::collections::BTreeMap;

use super::coin::Coin;
use super::entry::RecyclerEntry;
use super::error::CoinageError;
use super::operation::LockSet;
use super::params::{CoinageParameters, canonical_breakdown};
use super::types::{
    Amount, CoinIndex, DenominationExponent, EntryIndex, PurseId, RingIndex, Timestamp,
};

/// What denominations the caller needs selection to produce.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum OutputRequirement {
    /// Any denominations are acceptable as long as they total the requested
    /// amount. Export and rebalance use this: the coins either leave under
    /// their own secrets or move into another purse, so their shape is free.
    AnyDenominations,
    /// The produced coins must have exactly these denominations. Transfer uses
    /// this, because each output is destined for a separately named recipient
    /// account.
    Exact(Vec<DenominationExponent>),
}

/// A request to produce value from a purse.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SelectionRequest {
    /// Total value to produce.
    pub amount: Amount,
    /// Shape the produced coins must take.
    pub outputs: OutputRequirement,
    /// Whether recycler entries below the anonymity floor may be used.
    pub allow_degraded: bool,
}

/// Which strategy produced a plan.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SelectionTier {
    /// Available coins already have the needed shape. No preparatory extrinsic.
    ExactMatch,
    /// One coin is split to make up the remainder. One extrinsic.
    Split,
    /// Recycler entries are unloaded into fresh coins. One extrinsic per group,
    /// each consuming an unload token.
    UnloadIntoCoins,
}

/// A coin selection chose.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SelectedCoin {
    /// Derivation index within the purse.
    pub index: CoinIndex,
    /// Denomination.
    pub exponent: DenominationExponent,
}

/// A split of one coin into the denominations the request needs plus change.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SplitStep {
    /// The coin being split.
    pub coin: SelectedCoin,
    /// Denominations produced toward the requested amount.
    pub target_outputs: Vec<DenominationExponent>,
    /// Denominations returned to the purse.
    pub change_outputs: Vec<DenominationExponent>,
}

/// Recycler entries of one denomination in one ring, unloaded together.
///
/// A group is one atomic extrinsic carrying one unload token, so grouping
/// directly determines how many tokens an operation spends. The group's output
/// value equals its input value: its own change absorbs whatever the request
/// does not need.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UnloadGroup {
    /// Ring the entries belong to.
    pub ring: RingIndex,
    /// Denomination shared by every entry in the group.
    pub exponent: DenominationExponent,
    /// Entries consumed, in deterministic order.
    pub entries: Vec<EntryIndex>,
    /// Denominations produced toward the requested amount.
    pub target_outputs: Vec<DenominationExponent>,
    /// Denominations returned to the purse.
    pub change_outputs: Vec<DenominationExponent>,
}

/// How an operation should produce the requested amount.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SelectionPlan {
    /// Strategy that produced this plan.
    pub tier: SelectionTier,
    /// Coins consumed as they are, with no preparatory extrinsic.
    pub whole_coins: Vec<SelectedCoin>,
    /// The coin to split, if the plan needs one.
    pub split: Option<SplitStep>,
    /// Entry groups to unload, each one extrinsic.
    pub unloads: Vec<UnloadGroup>,
}

impl SelectionPlan {
    /// Total value the plan directs toward the request.
    pub fn target_value(&self) -> Amount {
        let whole: Amount = self
            .whole_coins
            .iter()
            .map(|coin| coin.exponent.value())
            .sum();
        let split: Amount = self
            .split
            .iter()
            .flat_map(|step| step.target_outputs.iter())
            .map(|exponent| exponent.value())
            .sum();
        let unloaded: Amount = self
            .unloads
            .iter()
            .flat_map(|group| group.target_outputs.iter())
            .map(|exponent| exponent.value())
            .sum();

        [whole, split, unloaded]
            .into_iter()
            .fold(Amount::ZERO, |acc, part| {
                acc.checked_add(part).unwrap_or(acc)
            })
    }

    /// Number of preparatory extrinsics the plan needs before value can move.
    pub fn preparatory_extrinsics(&self) -> usize {
        usize::from(self.split.is_some()) + self.unloads.len()
    }

    /// Number of unload tokens the plan consumes.
    pub fn unload_tokens_required(&self) -> usize {
        self.unloads.len()
    }

    /// The records the operation must hold until it terminates.
    pub fn lock_set(&self, purse: PurseId) -> LockSet {
        let mut locks = LockSet::default();

        for coin in &self.whole_coins {
            locks.coins.push((purse, coin.index));
        }
        if let Some(step) = &self.split {
            locks.coins.push((purse, step.coin.index));
        }
        for group in &self.unloads {
            for entry in &group.entries {
                locks.entries.push((purse, *entry));
            }
        }

        locks
    }
}

/// Choose records to produce `request.amount` from a purse's local view.
///
/// `coins` and `entries` are the purse's records; non-selectable ones are
/// filtered out here rather than by the caller, so the failure classification
/// can tell "you have no funds" from "your funds are not ready yet".
pub fn select(
    request: &SelectionRequest,
    coins: &[Coin],
    entries: &[RecyclerEntry],
    params: &CoinageParameters,
    now: Timestamp,
) -> Result<SelectionPlan, CoinageError> {
    let targets = target_denominations(request)?;

    if request.amount.is_zero() {
        return Ok(SelectionPlan {
            tier: SelectionTier::ExactMatch,
            whole_coins: Vec::new(),
            split: None,
            unloads: Vec::new(),
        });
    }

    let available_coins = ordered_coins(coins);
    let available_entries = ordered_entries(entries, now, request.allow_degraded);

    if let Some(plan) = try_exact_match(request, &targets, &available_coins) {
        return Ok(plan);
    }
    if let Some(plan) = try_split(request, &targets, &available_coins, params) {
        return Ok(plan);
    }
    if let Some(plan) = try_unload(
        request,
        &targets,
        &available_coins,
        &available_entries,
        params,
    ) {
        return Ok(plan);
    }

    Err(classify_failure(
        request,
        coins,
        entries,
        &available_coins,
        &available_entries,
    ))
}

/// The denominations a plan must produce, largest first.
fn target_denominations(
    request: &SelectionRequest,
) -> Result<Vec<DenominationExponent>, CoinageError> {
    match &request.outputs {
        OutputRequirement::AnyDenominations => canonical_breakdown(request.amount)
            .ok_or_else(|| CoinageError::Internal("amount exceeds supported denominations".into())),
        OutputRequirement::Exact(outputs) => {
            let total: Amount = outputs.iter().map(|exponent| exponent.value()).sum();
            if total != request.amount {
                return Err(CoinageError::OutputsDoNotSumToAmount);
            }

            let mut sorted = outputs.clone();
            sorted.sort_by(|left, right| right.cmp(left));
            Ok(sorted)
        }
    }
}

/// Selectable coins in the layer's canonical order: largest denomination first,
/// then oldest, then lowest index.
///
/// Preferring older coins is what makes payment traffic refresh a wallet
/// implicitly, so the age sweep has less to do.
fn ordered_coins(coins: &[Coin]) -> Vec<&Coin> {
    let mut selectable: Vec<&Coin> = coins.iter().filter(|coin| coin.is_selectable()).collect();
    selectable.sort_by(|left, right| {
        right
            .exponent
            .cmp(&left.exponent)
            .then(right.age.cmp(&left.age))
            .then(left.index.cmp(&right.index))
    });
    selectable
}

/// Selectable entries in the layer's canonical order: largest denomination
/// first, then lowest ring, then lowest index.
fn ordered_entries(
    entries: &[RecyclerEntry],
    now: Timestamp,
    allow_degraded: bool,
) -> Vec<&RecyclerEntry> {
    let mut selectable: Vec<&RecyclerEntry> = entries
        .iter()
        .filter(|entry| entry.is_selectable(now, allow_degraded))
        .collect();
    selectable.sort_by(|left, right| {
        right
            .exponent
            .cmp(&left.exponent)
            .then(ring_sort_key(left).cmp(&ring_sort_key(right)))
            .then(left.index.cmp(&right.index))
    });
    selectable
}

/// Ringless entries sort last; they are filtered out before this runs, so the
/// fallback only guards against an inconsistent snapshot.
fn ring_sort_key(entry: &RecyclerEntry) -> u32 {
    entry.ring.map_or(u32::MAX, |ring| ring.0)
}

/// Tier 1: the purse already holds coins of the right shape.
fn try_exact_match(
    request: &SelectionRequest,
    targets: &[DenominationExponent],
    available: &[&Coin],
) -> Option<SelectionPlan> {
    let chosen = match &request.outputs {
        // Any shape will do, so take the largest coins that still fit. With
        // power-of-two denominations this greedy pass finds an exact subset
        // whenever one exists.
        OutputRequirement::AnyDenominations => {
            let mut remaining = request.amount;
            let mut chosen = Vec::new();

            for coin in available {
                if coin.value() <= remaining {
                    remaining = remaining.saturating_sub(coin.value());
                    chosen.push(selected(coin));
                    if remaining.is_zero() {
                        break;
                    }
                }
            }

            remaining.is_zero().then_some(chosen)?
        }
        // Each output goes to its own account, so a coin can only serve a
        // target of exactly its denomination.
        OutputRequirement::Exact(_) => {
            let mut used = vec![false; available.len()];
            let mut chosen = Vec::new();

            for target in targets {
                let position = available
                    .iter()
                    .enumerate()
                    .position(|(index, coin)| !used[index] && coin.exponent == *target)?;
                used[position] = true;
                chosen.push(selected(available[position]));
            }

            chosen
        }
    };

    Some(SelectionPlan {
        tier: SelectionTier::ExactMatch,
        whole_coins: chosen,
        split: None,
        unloads: Vec::new(),
    })
}

/// Tier 2: one split extrinsic makes up what whole coins cannot.
///
/// The spec's preference order is deliberate — a single oversized coin is tried
/// before a multi-coin cover, so the common case spends one coin rather than
/// fragmenting several.
fn try_split(
    request: &SelectionRequest,
    targets: &[DenominationExponent],
    available: &[&Coin],
    params: &CoinageParameters,
) -> Option<SelectionPlan> {
    if let Some(plan) = split_single(request.amount, targets, available, &[], params) {
        return Some(plan);
    }

    // Multi-coin cover: take whole coins in order while they fit under the
    // remainder, then split the coin that crosses it.
    let mut remaining = request.amount;
    let mut unmet: Vec<DenominationExponent> = targets.to_vec();
    let mut whole = Vec::new();
    let mut consumed = Vec::new();

    for (position, coin) in available.iter().enumerate() {
        if remaining.is_zero() {
            break;
        }
        if coin.value() > remaining {
            continue;
        }
        // Under `Exact`, a whole coin is only useful if some unmet target has
        // precisely its denomination.
        if matches!(request.outputs, OutputRequirement::Exact(_)) {
            match unmet.iter().position(|target| *target == coin.exponent) {
                Some(target) => {
                    unmet.remove(target);
                }
                None => continue,
            }
        }

        remaining = remaining.saturating_sub(coin.value());
        whole.push(selected(coin));
        consumed.push(position);
    }

    if remaining.is_zero() || whole.is_empty() {
        return None;
    }

    let unmet_targets = match &request.outputs {
        OutputRequirement::AnyDenominations => canonical_breakdown(remaining)?,
        OutputRequirement::Exact(_) => unmet,
    };

    let mut plan = split_single(remaining, &unmet_targets, available, &consumed, params)?;
    plan.whole_coins.splice(0..0, whole);
    Some(plan)
}

/// Find the smallest unused coin that covers `remaining` and split it.
///
/// The spec phrases this as *strictly* greater than the remainder, which holds
/// when any shape will do: a coin worth exactly the remainder would already
/// have been taken whole by tier 1. Under `Exact` that is not so — a coin can
/// match the value and still be the wrong shape, as when one 16-cent coin must
/// become two 8-cent outputs to two accounts — so equality qualifies too, and
/// the split simply produces no change.
fn split_single(
    remaining: Amount,
    unmet_targets: &[DenominationExponent],
    available: &[&Coin],
    consumed: &[usize],
    params: &CoinageParameters,
) -> Option<SelectionPlan> {
    // `available` is largest-first, so searching from the back finds the
    // smallest coin that still covers the remainder.
    let candidate = available
        .iter()
        .enumerate()
        .rfind(|(position, coin)| !consumed.contains(position) && coin.value() >= remaining)?;

    let (_, coin) = candidate;
    let change = coin.value().checked_sub(remaining)?;
    let change_outputs = canonical_breakdown(change)?;

    let total_outputs = unmet_targets.len() + change_outputs.len();
    if total_outputs > params.max_split_outputs as usize {
        return None;
    }

    Some(SelectionPlan {
        tier: SelectionTier::Split,
        whole_coins: Vec::new(),
        split: Some(SplitStep {
            coin: selected(coin),
            target_outputs: unmet_targets.to_vec(),
            change_outputs,
        }),
        unloads: Vec::new(),
    })
}

/// Tier 3: mint fresh coins by unloading recycler entries.
fn try_unload(
    request: &SelectionRequest,
    targets: &[DenominationExponent],
    available_coins: &[&Coin],
    available_entries: &[&RecyclerEntry],
    params: &CoinageParameters,
) -> Option<SelectionPlan> {
    if available_entries.is_empty() {
        return None;
    }

    // Whole coins cover what they can without overshooting; entries make up the
    // deficit.
    let mut remaining = request.amount;
    let mut unmet: Vec<DenominationExponent> = targets.to_vec();
    let mut whole = Vec::new();

    for coin in available_coins {
        if remaining.is_zero() || coin.value() > remaining {
            continue;
        }
        if matches!(request.outputs, OutputRequirement::Exact(_)) {
            match unmet.iter().position(|target| *target == coin.exponent) {
                Some(target) => {
                    unmet.remove(target);
                }
                None => continue,
            }
        }

        remaining = remaining.saturating_sub(coin.value());
        whole.push(selected(coin));
    }

    if remaining.is_zero() {
        return None;
    }

    let chosen = choose_entries(remaining, available_entries)?;
    let groups = group_entries(&chosen, params);

    let unloads = assign_outputs(groups, &request.outputs, remaining, unmet, params)?;

    Some(SelectionPlan {
        tier: SelectionTier::UnloadIntoCoins,
        whole_coins: whole,
        split: None,
        unloads,
    })
}

/// Prefer one entry that covers the deficit on its own; otherwise take entries
/// in order until they do.
fn choose_entries<'a>(
    deficit: Amount,
    available: &[&'a RecyclerEntry],
) -> Option<Vec<&'a RecyclerEntry>> {
    if let Some(single) = available.iter().rfind(|entry| entry.value() >= deficit) {
        return Some(vec![single]);
    }

    let mut covered = Amount::ZERO;
    let mut chosen = Vec::new();

    for entry in available {
        covered = covered.checked_add(entry.value())?;
        chosen.push(*entry);
        if covered >= deficit {
            return Some(chosen);
        }
    }

    None
}

/// Bucket entries by `(denomination, ring)`, respecting the pallet's
/// consolidation cap. Buckets keep the order in which they were first seen, so
/// grouping stays deterministic.
fn group_entries(
    chosen: &[&RecyclerEntry],
    params: &CoinageParameters,
) -> Vec<(DenominationExponent, RingIndex, Vec<EntryIndex>)> {
    let mut buckets: BTreeMap<(DenominationExponent, u32), Vec<EntryIndex>> = BTreeMap::new();
    let mut order: Vec<(DenominationExponent, u32)> = Vec::new();

    for entry in chosen {
        let Some(ring) = entry.ring else {
            continue;
        };
        let key = (entry.exponent, ring.0);
        if !buckets.contains_key(&key) {
            order.push(key);
        }
        buckets.entry(key).or_default().push(entry.index);
    }

    let cap = params.max_recycler_entries_per_group.max(1) as usize;
    let mut groups = Vec::new();

    for key in order {
        let Some(indices) = buckets.remove(&key) else {
            continue;
        };
        for chunk in indices.chunks(cap) {
            groups.push((key.0, RingIndex(key.1), chunk.to_vec()));
        }
    }

    groups
}

/// Hand each group as much of the outstanding request as it can carry; whatever
/// a group does not spend comes back as its own change.
///
/// The two output requirements need different arithmetic. When any shape will
/// do, a group contributes value and its outputs are derived from what it
/// contributed — so a request for 20 cents can be met by three small groups
/// none of which could mint a 16-cent coin on its own. When the caller named
/// the denominations, each one must be minted whole by a single group, because
/// a coin cannot span two extrinsics.
fn assign_outputs(
    groups: Vec<(DenominationExponent, RingIndex, Vec<EntryIndex>)>,
    outputs: &OutputRequirement,
    deficit: Amount,
    unmet_targets: Vec<DenominationExponent>,
    params: &CoinageParameters,
) -> Option<Vec<UnloadGroup>> {
    let mut outstanding_value = deficit;
    let mut outstanding_targets = unmet_targets;
    let mut unloads = Vec::new();

    for (exponent, ring, entries) in groups {
        let group_value =
            Amount::from_cents(exponent.value().cents().checked_mul(entries.len() as u64)?);

        let (target_outputs, spent) = match outputs {
            OutputRequirement::AnyDenominations => {
                let contribution = group_value.min(outstanding_value);
                (canonical_breakdown(contribution)?, contribution)
            }
            OutputRequirement::Exact(_) => {
                let mut budget = group_value;
                let mut chosen = Vec::new();
                let mut index = 0;

                while index < outstanding_targets.len() {
                    let candidate = outstanding_targets[index];
                    if candidate.value() <= budget {
                        budget = budget.saturating_sub(candidate.value());
                        chosen.push(candidate);
                        outstanding_targets.remove(index);
                    } else {
                        index += 1;
                    }
                }

                let spent = group_value.saturating_sub(budget);
                (chosen, spent)
            }
        };

        outstanding_value = outstanding_value.saturating_sub(spent);
        let change_outputs = canonical_breakdown(group_value.saturating_sub(spent))?;

        if target_outputs.len() + change_outputs.len() > params.max_split_outputs as usize {
            return None;
        }

        unloads.push(UnloadGroup {
            ring,
            exponent,
            entries,
            target_outputs,
            change_outputs,
        });
    }

    // Nothing may be left over. Which ledger has to balance depends on the
    // requirement: value when any shape will do, named denominations otherwise.
    let settled = match outputs {
        OutputRequirement::AnyDenominations => outstanding_value.is_zero(),
        OutputRequirement::Exact(_) => outstanding_targets.is_empty(),
    };
    settled.then_some(unloads)
}

/// Explain why no strategy succeeded.
///
/// The three outcomes call for different responses from the caller, so the
/// distinction is worth drawing precisely:
///
/// - Not enough value exists, even counting every entry that is merely waiting
///   — a dead end until the purse is funded.
/// - Enough exists but some of it is not selectable yet — resolves on its own
///   once rings fill and jitter elapses, so the caller should retry later.
/// - Everything that will ever be selectable already is, and it covers the
///   amount, yet no plan could be built — waiting will not help, because the
///   obstacle is shape rather than quantity.
fn classify_failure(
    request: &SelectionRequest,
    coins: &[Coin],
    entries: &[RecyclerEntry],
    available_coins: &[&Coin],
    available_entries: &[&RecyclerEntry],
) -> CoinageError {
    use super::entry::EntryLocalState;

    let coins_now: Amount = available_coins.iter().map(|coin| coin.value()).sum();
    let entries_now: Amount = available_entries.iter().map(|entry| entry.value()).sum();
    let available = coins_now.checked_add(entries_now).unwrap_or(coins_now);

    // What the purse could offer if every entry were ready and degraded rings
    // were acceptable. Locked and terminal records stay excluded: they are not
    // waiting on anything the caller can outlast.
    let eventual_entries: Amount = entries
        .iter()
        .filter(|entry| entry.local == EntryLocalState::Available)
        .map(|entry| entry.value())
        .sum();
    let selectable_coins: Amount = coins
        .iter()
        .filter(|coin| coin.is_selectable())
        .map(|coin| coin.value())
        .sum();
    let available_when_ready = selectable_coins
        .checked_add(eventual_entries)
        .unwrap_or(selectable_coins);

    if available_when_ready < request.amount {
        CoinageError::InsufficientFunds {
            requested: request.amount,
            available,
        }
    } else if available_when_ready > available {
        CoinageError::NoReadyEntries {
            requested: request.amount,
            available_when_ready,
        }
    } else {
        CoinageError::UnsatisfiableOutputs {
            requested: request.amount,
            available,
        }
    }
}

fn selected(coin: &Coin) -> SelectedCoin {
    SelectedCoin {
        index: coin.index,
        exponent: coin.exponent,
    }
}

#[cfg(test)]
mod tests {
    use core::time::Duration;

    use super::super::entry::EntryOnChainState;
    use super::super::types::CoinAge;
    use super::*;

    const NOW: Timestamp = Timestamp(1_000_000);

    fn exponent(value: u8) -> DenominationExponent {
        DenominationExponent::new(value).expect("exponent is in range")
    }

    fn coin(index: u32, exponent_value: u8, age: u16) -> Coin {
        let mut coin = Coin::pending(PurseId::MAIN, CoinIndex(index), exponent(exponent_value));
        coin.observe_populated(CoinAge(age))
            .expect("observe is valid");
        coin
    }

    fn entry(index: u32, exponent_value: u8, ring: u32) -> RecyclerEntry {
        let mut entry = RecyclerEntry::allocated(
            PurseId::MAIN,
            EntryIndex(index),
            exponent(exponent_value),
            Timestamp(0),
            Duration::ZERO,
        );
        entry.ring = Some(RingIndex(ring));
        entry.on_chain = EntryOnChainState::Ready;
        entry
    }

    fn request(cents: u64) -> SelectionRequest {
        SelectionRequest {
            amount: Amount::from_cents(cents),
            outputs: OutputRequirement::AnyDenominations,
            allow_degraded: true,
        }
    }

    fn exact_request(cents: u64, outputs: &[u8]) -> SelectionRequest {
        SelectionRequest {
            amount: Amount::from_cents(cents),
            outputs: OutputRequirement::Exact(outputs.iter().copied().map(exponent).collect()),
            allow_degraded: true,
        }
    }

    fn select_from(
        request: &SelectionRequest,
        coins: &[Coin],
        entries: &[RecyclerEntry],
    ) -> Result<SelectionPlan, CoinageError> {
        select(request, coins, entries, &CoinageParameters::default(), NOW)
    }

    #[test]
    fn ordering_is_largest_then_oldest_then_lowest_index() {
        let coins = vec![
            coin(5, 2, 1),
            coin(1, 4, 0),
            coin(2, 4, 3),
            coin(0, 4, 3),
            coin(9, 3, 7),
        ];

        let ordered: Vec<u32> = ordered_coins(&coins).iter().map(|c| c.index.0).collect();

        assert_eq!(ordered, vec![0, 2, 1, 9, 5]);
    }

    #[test]
    fn entry_ordering_is_largest_then_lowest_ring_then_lowest_index() {
        let entries = vec![
            entry(3, 2, 1),
            entry(1, 4, 7),
            entry(2, 4, 2),
            entry(0, 4, 2),
        ];

        let ordered: Vec<u32> = ordered_entries(&entries, NOW, true)
            .iter()
            .map(|e| e.index.0)
            .collect();

        assert_eq!(ordered, vec![0, 2, 1, 3]);
    }

    #[test]
    fn unselectable_records_are_never_offered() {
        let mut locked = coin(0, 4, 0);
        locked
            .lock_for(super::super::types::OperationHandle(1))
            .expect("lock is valid");
        let coins = vec![
            locked,
            Coin::pending(PurseId::MAIN, CoinIndex(1), exponent(4)),
        ];

        assert!(ordered_coins(&coins).is_empty());
    }

    #[test]
    fn a_zero_amount_selects_nothing() {
        let plan = select_from(&request(0), &[], &[]).expect("zero is always satisfiable");

        assert_eq!(plan.tier, SelectionTier::ExactMatch);
        assert!(plan.whole_coins.is_empty());
        assert_eq!(plan.preparatory_extrinsics(), 0);
    }

    #[test]
    fn exact_match_needs_no_preparatory_extrinsic() {
        let coins = vec![coin(0, 3, 0), coin(1, 2, 0)];

        let plan = select_from(&request(12), &coins, &[]).expect("12 = 8 + 4");

        assert_eq!(plan.tier, SelectionTier::ExactMatch);
        assert_eq!(plan.preparatory_extrinsics(), 0);
        assert_eq!(plan.unload_tokens_required(), 0);
        assert_eq!(plan.target_value(), Amount::from_cents(12));
    }

    #[test]
    fn exact_match_prefers_larger_and_older_coins() {
        let coins = vec![coin(0, 3, 0), coin(1, 3, 5), coin(2, 2, 0)];

        let plan = select_from(&request(8), &coins, &[]).expect("one 8-cent coin suffices");

        assert_eq!(plan.whole_coins.len(), 1);
        assert_eq!(plan.whole_coins[0].index, CoinIndex(1));
    }

    #[test]
    fn exact_match_finds_a_subset_of_smaller_coins() {
        // 16 is reachable as 8 + 4 + 4 even though a single 32 coin overshoots.
        let coins = vec![coin(0, 5, 0), coin(1, 3, 0), coin(2, 2, 0), coin(3, 2, 0)];

        let plan = select_from(&request(16), &coins, &[]).expect("8 + 4 + 4 = 16");

        assert_eq!(plan.tier, SelectionTier::ExactMatch);
        assert_eq!(plan.target_value(), Amount::from_cents(16));
        assert_eq!(plan.whole_coins.len(), 3);
    }

    #[test]
    fn split_takes_the_smallest_coin_that_covers_the_amount() {
        let coins = vec![coin(0, 6, 0), coin(1, 5, 0), coin(2, 4, 0)];

        let plan = select_from(&request(12), &coins, &[]).expect("split the 16-cent coin");

        assert_eq!(plan.tier, SelectionTier::Split);
        let step = plan.split.as_ref().expect("a split step is present");
        assert_eq!(step.coin.index, CoinIndex(2));
        assert_eq!(step.target_outputs, vec![exponent(3), exponent(2)]);
        assert_eq!(step.change_outputs, vec![exponent(2)]);
        assert_eq!(plan.preparatory_extrinsics(), 1);
    }

    #[test]
    fn split_output_value_is_conserved() {
        let coins = vec![coin(0, 5, 0)];

        let plan = select_from(&request(20), &coins, &[]).expect("split the 32-cent coin");
        let step = plan.split.as_ref().expect("a split step is present");

        let produced: Amount = step
            .target_outputs
            .iter()
            .chain(step.change_outputs.iter())
            .map(|exponent| exponent.value())
            .sum();

        assert_eq!(produced, Amount::from_cents(32));
        assert_eq!(plan.target_value(), Amount::from_cents(20));
    }

    #[test]
    fn split_falls_back_to_a_multi_coin_cover() {
        // No single coin exceeds 24, but 16 whole plus a split of 16 reaches it.
        let coins = vec![coin(0, 4, 0), coin(1, 4, 0)];

        let plan = select_from(&request(24), &coins, &[]).expect("16 + split(16)");

        assert_eq!(plan.tier, SelectionTier::Split);
        assert_eq!(plan.whole_coins.len(), 1);
        let step = plan.split.as_ref().expect("a split step is present");
        assert_eq!(step.target_outputs, vec![exponent(3)]);
        assert_eq!(step.change_outputs, vec![exponent(3)]);
        assert_eq!(plan.target_value(), Amount::from_cents(24));
    }

    #[test]
    fn unload_is_used_only_when_coins_cannot_cover_the_amount() {
        let entries = vec![entry(0, 5, 1)];

        let plan = select_from(&request(24), &[], &entries).expect("unload the 32-cent entry");

        assert_eq!(plan.tier, SelectionTier::UnloadIntoCoins);
        assert_eq!(plan.unload_tokens_required(), 1);
        assert_eq!(plan.target_value(), Amount::from_cents(24));

        let group = &plan.unloads[0];
        assert_eq!(group.entries, vec![EntryIndex(0)]);
        assert_eq!(group.target_outputs, vec![exponent(4), exponent(3)]);
        assert_eq!(group.change_outputs, vec![exponent(3)]);
    }

    #[test]
    fn unload_group_output_value_equals_its_input_value() {
        let entries = vec![entry(0, 4, 1), entry(1, 4, 1)];

        let plan = select_from(&request(20), &[], &entries).expect("two 16-cent entries cover 20");

        let group = &plan.unloads[0];
        let produced: Amount = group
            .target_outputs
            .iter()
            .chain(group.change_outputs.iter())
            .map(|exponent| exponent.value())
            .sum();

        assert_eq!(produced, Amount::from_cents(32));
        assert_eq!(plan.target_value(), Amount::from_cents(20));
    }

    #[test]
    fn unload_prefers_a_single_sufficient_entry() {
        let entries = vec![entry(0, 6, 1), entry(1, 5, 1), entry(2, 3, 1)];

        let plan = select_from(&request(20), &[], &entries).expect("one 32-cent entry covers 20");

        assert_eq!(plan.unloads.len(), 1);
        assert_eq!(plan.unloads[0].entries, vec![EntryIndex(1)]);
    }

    #[test]
    fn unload_combines_whole_coins_with_entries() {
        let coins = vec![coin(0, 3, 0)];
        let entries = vec![entry(0, 3, 1)];

        let plan = select_from(&request(16), &coins, &entries).expect("8 whole + 8 unloaded");

        assert_eq!(plan.tier, SelectionTier::UnloadIntoCoins);
        assert_eq!(plan.whole_coins.len(), 1);
        assert_eq!(plan.unloads.len(), 1);
        assert_eq!(plan.target_value(), Amount::from_cents(16));
    }

    #[test]
    fn entries_are_grouped_by_denomination_and_ring() {
        let entries = vec![
            entry(0, 4, 1),
            entry(1, 4, 1),
            entry(2, 4, 2),
            entry(3, 3, 1),
        ];

        let plan = select_from(&request(56), &[], &entries).expect("all four entries are needed");

        // One extrinsic and one unload token per (denomination, ring) bucket.
        assert_eq!(plan.unloads.len(), 3);
        assert_eq!(plan.unload_tokens_required(), 3);
        assert_eq!(plan.unloads[0].entries, vec![EntryIndex(0), EntryIndex(1)]);
        assert_eq!(plan.unloads[1].entries, vec![EntryIndex(2)]);
        assert_eq!(plan.unloads[2].entries, vec![EntryIndex(3)]);
        assert_eq!(plan.target_value(), Amount::from_cents(56));
    }

    #[test]
    fn a_group_never_exceeds_the_consolidation_cap() {
        let params = CoinageParameters {
            max_recycler_entries_per_group: 2,
            ..CoinageParameters::default()
        };
        let entries: Vec<RecyclerEntry> = (0..5).map(|index| entry(index, 2, 1)).collect();

        let plan = select(&request(20), &[], &entries, &params, NOW).expect("five 4-cent entries");

        assert!(plan.unloads.iter().all(|group| group.entries.len() <= 2));
        assert_eq!(plan.target_value(), Amount::from_cents(20));
    }

    #[test]
    fn degraded_entries_are_excluded_when_the_caller_forbids_them() {
        let mut degraded = entry(0, 5, 1);
        degraded.on_chain = EntryOnChainState::Degraded(3);
        let entries = vec![degraded];

        let permissive = SelectionRequest {
            allow_degraded: true,
            ..request(32)
        };
        let strict = SelectionRequest {
            allow_degraded: false,
            ..request(32)
        };

        assert!(select_from(&permissive, &[], &entries).is_ok());
        assert!(matches!(
            select_from(&strict, &[], &entries),
            Err(CoinageError::NoReadyEntries { .. })
        ));
    }

    #[test]
    fn waiting_entries_report_no_ready_entries_rather_than_insufficient_funds() {
        let mut waiting = entry(0, 5, 1);
        waiting.on_chain = EntryOnChainState::Waiting;

        let error = select_from(&request(32), &[], &[waiting]).expect_err("nothing is selectable");

        assert_eq!(
            error,
            CoinageError::NoReadyEntries {
                requested: Amount::from_cents(32),
                available_when_ready: Amount::from_cents(32),
            }
        );
    }

    #[test]
    fn an_empty_purse_reports_insufficient_funds() {
        let error = select_from(&request(8), &[], &[]).expect_err("nothing to select");

        assert_eq!(
            error,
            CoinageError::InsufficientFunds {
                requested: Amount::from_cents(8),
                available: Amount::ZERO,
            }
        );
    }

    #[test]
    fn shortfall_beyond_any_waiting_value_reports_insufficient_funds() {
        let mut waiting = entry(0, 2, 1);
        waiting.on_chain = EntryOnChainState::Waiting;
        let coins = vec![coin(0, 2, 0)];

        let error =
            select_from(&request(1_000), &coins, &[waiting]).expect_err("nowhere near enough");

        assert!(matches!(error, CoinageError::InsufficientFunds { .. }));
    }

    #[test]
    fn coins_that_cannot_be_merged_report_unsatisfiable_outputs() {
        // Two 8-cent coins hold the requested value, but coinage can split a
        // coin and never merge two, so a single 16-cent output is unreachable.
        let coins = vec![coin(0, 3, 0), coin(1, 3, 0)];

        let error = select_from(&exact_request(16, &[4]), &coins, &[])
            .expect_err("no 16-cent coin can be formed");

        assert_eq!(
            error,
            CoinageError::UnsatisfiableOutputs {
                requested: Amount::from_cents(16),
                available: Amount::from_cents(16),
            }
        );
    }

    #[test]
    fn a_denomination_no_group_can_mint_reports_unsatisfiable_outputs() {
        // Enough value across five entries, but a named 16-cent output has to
        // be minted whole by one group, and the cap holds groups to 8 cents.
        let params = CoinageParameters {
            max_recycler_entries_per_group: 2,
            ..CoinageParameters::default()
        };
        let entries: Vec<RecyclerEntry> = (0..5).map(|index| entry(index, 2, 1)).collect();
        let request = exact_request(16, &[4]);

        let error =
            select(&request, &[], &entries, &params, NOW).expect_err("no group reaches 16 cents");

        assert_eq!(
            error,
            CoinageError::UnsatisfiableOutputs {
                requested: Amount::from_cents(16),
                available: Amount::from_cents(20),
            }
        );
    }

    #[test]
    fn waiting_value_outranks_an_unsatisfiable_shape() {
        // The shape is unreachable from what is selectable now, but an entry is
        // still ripening, so the caller is told to wait rather than told it is
        // impossible.
        let coins = vec![coin(0, 3, 0), coin(1, 3, 0)];
        let mut waiting = entry(0, 4, 1);
        waiting.on_chain = EntryOnChainState::Waiting;

        let error = select_from(&exact_request(16, &[4]), &coins, &[waiting])
            .expect_err("nothing selectable can form a 16-cent coin");

        assert_eq!(
            error,
            CoinageError::NoReadyEntries {
                requested: Amount::from_cents(16),
                available_when_ready: Amount::from_cents(32),
            }
        );
    }

    #[test]
    fn exact_outputs_must_sum_to_the_amount() {
        let error =
            select_from(&exact_request(12, &[3]), &[], &[]).expect_err("8 does not sum to 12");

        assert_eq!(error, CoinageError::OutputsDoNotSumToAmount);
    }

    #[test]
    fn exact_outputs_match_coins_denomination_for_denomination() {
        let coins = vec![coin(0, 3, 0), coin(1, 3, 0), coin(2, 4, 0)];

        let plan = select_from(&exact_request(16, &[3, 3]), &coins, &[])
            .expect("two 8-cent coins are held");

        assert_eq!(plan.tier, SelectionTier::ExactMatch);
        assert_eq!(plan.whole_coins.len(), 2);
        assert!(
            plan.whole_coins
                .iter()
                .all(|coin| coin.exponent == exponent(3))
        );
    }

    #[test]
    fn exact_outputs_split_when_the_shape_is_wrong() {
        // The purse holds one 16-cent coin but the caller wants two 8-cent
        // outputs to two accounts, so a whole transfer cannot serve it.
        let coins = vec![coin(0, 4, 0)];

        let plan =
            select_from(&exact_request(16, &[3, 3]), &coins, &[]).expect("split the 16-cent coin");

        assert_eq!(plan.tier, SelectionTier::Split);
        let step = plan.split.as_ref().expect("a split step is present");
        assert_eq!(step.target_outputs, vec![exponent(3), exponent(3)]);
        assert!(step.change_outputs.is_empty());
    }

    #[test]
    fn the_lock_set_covers_every_record_the_plan_touches() {
        let coins = vec![coin(0, 3, 0)];
        let entries = vec![entry(7, 3, 1)];

        let plan = select_from(&request(16), &coins, &entries).expect("8 whole + 8 unloaded");
        let locks = plan.lock_set(PurseId::MAIN);

        assert_eq!(locks.coins, vec![(PurseId::MAIN, CoinIndex(0))]);
        assert_eq!(locks.entries, vec![(PurseId::MAIN, EntryIndex(7))]);
    }

    #[test]
    fn the_lock_set_includes_the_split_coin() {
        let coins = vec![coin(4, 5, 0)];

        let plan = select_from(&request(20), &coins, &[]).expect("split the 32-cent coin");
        let locks = plan.lock_set(PurseId::MAIN);

        assert_eq!(locks.coins, vec![(PurseId::MAIN, CoinIndex(4))]);
    }

    #[test]
    fn selection_is_deterministic_under_input_reordering() {
        let ordered = vec![coin(0, 4, 2), coin(1, 4, 2), coin(2, 3, 0), coin(3, 2, 1)];
        let shuffled = vec![coin(3, 2, 1), coin(1, 4, 2), coin(0, 4, 2), coin(2, 3, 0)];

        let first = select_from(&request(28), &ordered, &[]).expect("28 = 16 + 8 + 4");
        let second = select_from(&request(28), &shuffled, &[]).expect("28 = 16 + 8 + 4");

        assert_eq!(first, second);
    }
}
