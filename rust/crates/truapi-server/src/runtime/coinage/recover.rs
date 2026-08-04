//! Driving operation recovery against finalized chain state.
//!
//! `coinage-layer.md` §7.7. The decision procedure is pure and lives in
//! [`crate::host_logic::coinage::recovery`]; this module supplies it with the
//! chain reads it needs and applies what it decides.
//!
//! Every read is pinned to one finalized block hash. That is not a detail: the
//! whole point is that a decision made here cannot be undone, and a read taken
//! at the best block could be describing a fork that is about to disappear.
//!
//! Recovery runs at layer start, before any new operation is accepted, and
//! whenever tracking reports [`super::submit::TrackerOutcome::Unknown`].

use crate::host_logic::coinage::error::CoinageError;
use crate::host_logic::coinage::log::{LogEntry, LogEntryState};
use crate::host_logic::coinage::operation::LockSet;
use crate::host_logic::coinage::recovery::{self, RecordObservation, Resolution};
use crate::host_logic::coinage::store::CoinageStore;
use crate::host_logic::coinage::types::{BlockHash, OperationHandle};
use crate::runtime::statement_allowance::rpc::RpcClient;

/// A finalized block every read in one recovery pass is pinned to.
#[derive(Debug, Clone)]
pub struct FinalizedAt {
    /// Block hash, as the node spells it.
    pub hash: String,
    /// Decoded block hash, for the log.
    pub block_hash: BlockHash,
    /// Block height, for the expiry test.
    pub number: u64,
}

/// What one recovery pass resolved.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct PassOutcome {
    /// Transactions that definitely succeeded.
    pub succeeded: Vec<(OperationHandle, u32)>,
    /// Transactions that can never take effect.
    pub rejected: Vec<(OperationHandle, u32)>,
    /// Transactions dropped because a predecessor did not succeed.
    pub abandoned: Vec<(OperationHandle, u32)>,
    /// Transactions still undecided; ask again at the next finalized block.
    pub still_pending: Vec<(OperationHandle, u32)>,
}

impl PassOutcome {
    /// Whether anything is still waiting on a later finalized block.
    pub fn is_complete(&self) -> bool {
        self.still_pending.is_empty()
    }
}

/// Read the finalized head as the anchor for a recovery pass.
pub async fn finalized_at(rpc: &RpcClient) -> Result<FinalizedAt, CoinageError> {
    let hash = rpc
        .finalized_head()
        .await
        .map_err(|error| CoinageError::SubscriptionError(error.to_string()))?;
    let number = super::observe::block_number(rpc, &hash).await?;
    let block_hash = super::observe::decode_block_hash(&hash)?;

    Ok(FinalizedAt {
        hash,
        block_hash,
        number,
    })
}

/// Resolve every pending transaction that can be decided at `at`.
///
/// Runs the abandonment cascade first, then decides each entry whose
/// dependencies are settled. Entries whose dependencies are still open are
/// reported as pending without being read, because their observations cannot be
/// interpreted yet (§7.5).
pub async fn run_pass(
    rpc: &RpcClient,
    store: &mut CoinageStore,
    entropy: &[u8],
    at: &FinalizedAt,
) -> Result<PassOutcome, CoinageError> {
    let mut outcome = PassOutcome::default();

    let handles: Vec<OperationHandle> = store
        .open_operations()
        .filter(|operation| operation.log.has_pending())
        .map(|operation| operation.handle)
        .collect();

    for handle in handles {
        loop {
            // A cascade can settle entries without any chain read, and can
            // unblock further cascading, so it runs to a fixed point first.
            let cascaded = cascade(store, handle)?;
            outcome
                .abandoned
                .extend(cascaded.iter().map(|sequence| (handle, *sequence)));

            let Some(entry) = next_resolvable(store, handle) else {
                break;
            };
            let sequence = entry.sequence;
            let observation = observe(rpc, entropy, &entry, at).await?;
            let resolution = recovery::resolve(&entry, observation, at.number);

            match recovery::log_state(&resolution, at.block_hash) {
                None => {
                    outcome.still_pending.push((handle, sequence));
                    break;
                }
                Some(state) => {
                    let succeeded = matches!(resolution, Resolution::Succeeded { .. });
                    store.resolve_transaction(handle, sequence, state)?;
                    if succeeded {
                        outcome.succeeded.push((handle, sequence));
                    } else {
                        outcome.rejected.push((handle, sequence));
                    }
                }
            }
        }

        // Anything still open after this handle's pass waits for a later block.
        if let Some(operation) = store.operation(handle) {
            for entry in operation.log.entries() {
                if entry.state.is_pending()
                    && !outcome.still_pending.contains(&(handle, entry.sequence))
                {
                    outcome.still_pending.push((handle, entry.sequence));
                }
            }
        }
    }

    Ok(outcome)
}

/// Apply the abandonment cascade and record it in the store.
fn cascade(store: &mut CoinageStore, handle: OperationHandle) -> Result<Vec<u32>, CoinageError> {
    let doomed: Vec<(u32, String)> = {
        let Some(operation) = store.operation(handle) else {
            return Ok(Vec::new());
        };
        let mut log = operation.log.clone();
        log.cascade_abandoned()
            .into_iter()
            .filter_map(|sequence| {
                let state = log.entry(sequence)?.state.clone();
                match state {
                    LogEntryState::Abandoned { reason } => Some((sequence, reason)),
                    _ => None,
                }
            })
            .collect()
    };

    for (sequence, reason) in &doomed {
        store.resolve_transaction(
            handle,
            *sequence,
            LogEntryState::Abandoned {
                reason: reason.clone(),
            },
        )?;
    }
    Ok(doomed.into_iter().map(|(sequence, _)| sequence).collect())
}

/// The next entry whose dependencies are all settled.
fn next_resolvable(store: &CoinageStore, handle: OperationHandle) -> Option<LogEntry> {
    let operation = store.operation(handle)?;
    let sequence = *operation.log.resolvable().first()?;
    operation.log.entry(sequence).cloned()
}

/// Ask the chain the two questions the decision needs, at a finalized block.
///
/// The input read is skipped when the outputs are already visible: that alone
/// settles the transaction as succeeded, and recovery may run over many pending
/// entries at every finalized block, so a read whose answer cannot change the
/// verdict is worth not making. `inputs_consumed` is therefore only meaningful
/// when `outputs_present` is false, which is exactly the precedence
/// [`recovery::resolve`] applies.
async fn observe(
    rpc: &RpcClient,
    entropy: &[u8],
    entry: &LogEntry,
    at: &FinalizedAt,
) -> Result<RecordObservation, CoinageError> {
    if all_present(rpc, entropy, &entry.outputs, at).await? {
        return Ok(RecordObservation {
            outputs_present: true,
            inputs_consumed: false,
        });
    }

    Ok(RecordObservation {
        outputs_present: false,
        inputs_consumed: none_present(rpc, entropy, &entry.inputs, at).await?,
    })
}

/// Whether every named record exists on chain at `at`.
///
/// An empty set is **not** "all present": a transaction with no outputs the
/// layer can see — a transfer, whose outputs belong to the recipient — must be
/// judged by its inputs instead, and answering `true` here would declare every
/// such transaction successful the moment it was planned.
async fn all_present(
    rpc: &RpcClient,
    entropy: &[u8],
    records: &LockSet,
    at: &FinalizedAt,
) -> Result<bool, CoinageError> {
    if records.is_empty() {
        return Ok(false);
    }
    for (purse, index) in &records.coins {
        if !super::observe::coin_present(rpc, entropy, *purse, *index, &at.hash).await? {
            return Ok(false);
        }
    }
    for (purse, index) in &records.entries {
        if !super::observe::entry_present(rpc, entropy, *purse, *index, &at.hash).await? {
            return Ok(false);
        }
    }
    Ok(true)
}

/// Whether every named record is gone from chain at `at`.
///
/// An empty set is not "all consumed", for the mirror-image reason: a
/// transaction that consumes nothing must not be read as having consumed
/// everything it was asked to.
async fn none_present(
    rpc: &RpcClient,
    entropy: &[u8],
    records: &LockSet,
    at: &FinalizedAt,
) -> Result<bool, CoinageError> {
    if records.is_empty() {
        return Ok(false);
    }
    for (purse, index) in &records.coins {
        if super::observe::coin_present(rpc, entropy, *purse, *index, &at.hash).await? {
            return Ok(false);
        }
    }
    for (purse, index) in &records.entries {
        if super::observe::entry_present(rpc, entropy, *purse, *index, &at.hash).await? {
            return Ok(false);
        }
    }
    Ok(true)
}

#[cfg(test)]
mod tests {
    use parity_scale_codec::Encode;
    use subxt_rpcs::RpcClient as HostRpcClient;

    use crate::host_logic::coinage::chain_constants::next_people_paseo;
    use crate::host_logic::coinage::coin::CoinState;
    use crate::host_logic::coinage::log::Checkpoint;
    use crate::host_logic::coinage::selection::{OutputRequirement, SelectionRequest};
    use crate::host_logic::coinage::types::{
        Amount, CoinAge, CoinIndex, DenominationExponent, OperationKind, PurseId, Timestamp,
    };
    use crate::runtime::coinage::storage::ChainCoin;
    use crate::runtime::statement_allowance::rpc::testing::ScriptedRpc;

    use super::*;

    const ENTROPY: [u8; 32] = [7; 32];
    const NOW: Timestamp = Timestamp(1_000_000);

    fn at(number: u64) -> FinalizedAt {
        FinalizedAt {
            hash: format!("0x{}", "07".repeat(32)),
            block_hash: BlockHash([7; 32]),
            number,
        }
    }

    fn checkpoint() -> Checkpoint {
        Checkpoint {
            number: 1_000,
            hash: BlockHash([1; 32]),
            mortality: 256,
        }
    }

    fn exponent(value: i8) -> DenominationExponent {
        DenominationExponent::new(value).expect("exponent is in range")
    }

    fn present() -> String {
        format!(
            "\"0x{}\"",
            hex::encode(ChainCoin { value: 3, age: 0 }.encode())
        )
    }

    fn absent() -> String {
        "null".to_string()
    }

    fn rpc(responses: &[String]) -> RpcClient {
        RpcClient::new(HostRpcClient::new(ScriptedRpc::new(
            responses.iter().map(String::as_str),
        )))
    }

    fn block_on<F: core::future::Future>(future: F) -> F::Output {
        futures::executor::block_on(future)
    }

    /// A store with one funded coin and one operation that has planned a
    /// transaction spending it to produce a fresh coin.
    fn in_flight() -> (CoinageStore, OperationHandle, CoinIndex, CoinIndex, u32) {
        let mut store = CoinageStore::new("Main".to_string());
        let input = store
            .add_pending_coin(PurseId::MAIN, exponent(3))
            .expect("purse exists");
        store
            .observe_coin(PurseId::MAIN, input, CoinAge(0))
            .expect("coin exists");

        let (handle, _plan) = store
            .begin_operation(
                PurseId::MAIN,
                OperationKind::Transfer,
                &SelectionRequest {
                    amount: Amount::from_cents(8),
                    outputs: OutputRequirement::AnyDenominations,
                    allow_degraded: true,
                },
                &next_people_paseo(),
                NOW,
            )
            .expect("8 cents are available");
        let output = store
            .add_pending_coin(PurseId::MAIN, exponent(3))
            .expect("purse exists");
        let inputs = store.operation(handle).expect("open").locks.clone();
        let sequence = store
            .plan_transaction(
                handle,
                inputs,
                LockSet {
                    coins: vec![(PurseId::MAIN, output)],
                    entries: Vec::new(),
                },
                checkpoint(),
                [],
            )
            .expect("open");

        (store, handle, input, output, sequence)
    }

    #[test]
    fn visible_outputs_settle_the_transaction_as_succeeded() {
        let (mut store, handle, input, _output, sequence) = in_flight();
        // outputs read first, and it is present, so the inputs are never read.
        let rpc = rpc(&[present()]);

        let outcome = block_on(run_pass(&rpc, &mut store, &ENTROPY, &at(1_100))).expect("passes");

        assert_eq!(outcome.succeeded, vec![(handle, sequence)]);
        assert!(outcome.is_complete());
        assert_eq!(
            store.coin(PurseId::MAIN, input).expect("exists").state,
            CoinState::Spent
        );
    }

    #[test]
    fn consumed_inputs_settle_a_transfer_whose_outputs_we_cannot_see() {
        let (mut store, handle, input, _output, sequence) = in_flight();
        // The output is absent (it went to a recipient) but the input is gone.
        let rpc = rpc(&[absent(), absent()]);

        let outcome = block_on(run_pass(&rpc, &mut store, &ENTROPY, &at(1_100))).expect("passes");

        assert_eq!(outcome.succeeded, vec![(handle, sequence)]);
        assert_eq!(
            store.coin(PurseId::MAIN, input).expect("exists").state,
            CoinState::Spent
        );
    }

    #[test]
    fn nothing_observed_inside_the_era_stays_pending_and_holds_its_locks() {
        let (mut store, handle, input, _output, sequence) = in_flight();
        // Output absent, input still present: undecided.
        let rpc = rpc(&[absent(), present()]);

        let outcome = block_on(run_pass(&rpc, &mut store, &ENTROPY, &at(1_100))).expect("passes");

        assert_eq!(outcome.still_pending, vec![(handle, sequence)]);
        assert!(!outcome.is_complete());
        assert!(
            matches!(
                store.coin(PurseId::MAIN, input).expect("exists").state,
                CoinState::LockedFor(_)
            ),
            "an undecided transaction keeps its inputs locked"
        );
    }

    #[test]
    fn an_expired_transaction_returns_its_inputs_to_the_pool() {
        let (mut store, handle, input, output, sequence) = in_flight();
        let rpc = rpc(&[absent(), present()]);

        let outcome = block_on(run_pass(&rpc, &mut store, &ENTROPY, &at(1_300))).expect("passes");

        assert_eq!(outcome.rejected, vec![(handle, sequence)]);
        assert!(outcome.is_complete());
        assert_eq!(
            store.coin(PurseId::MAIN, input).expect("exists").state,
            CoinState::Available,
            "past the era the transaction can never land, so the input is free"
        );
        assert_eq!(
            store.coin(PurseId::MAIN, output).expect("exists").state,
            CoinState::Spent,
            "the output never came to exist"
        );
    }

    #[test]
    fn a_rejected_head_abandons_its_dependant_without_any_chain_read() {
        let (mut store, handle, _input, output, first) = in_flight();
        let downstream = store
            .add_pending_coin(PurseId::MAIN, exponent(3))
            .expect("purse exists");
        let second = store
            .plan_transaction(
                handle,
                LockSet {
                    coins: vec![(PurseId::MAIN, output)],
                    entries: Vec::new(),
                },
                LockSet {
                    coins: vec![(PurseId::MAIN, downstream)],
                    entries: Vec::new(),
                },
                checkpoint(),
                [first],
            )
            .expect("open");
        // Only two responses are scripted: the head's two reads. The dependant
        // must be decided by the cascade alone — an extra read would panic the
        // scripted transport.
        let rpc = rpc(&[absent(), present()]);

        let outcome = block_on(run_pass(&rpc, &mut store, &ENTROPY, &at(1_300))).expect("passes");

        assert_eq!(outcome.rejected, vec![(handle, first)]);
        assert_eq!(outcome.abandoned, vec![(handle, second)]);
        assert!(outcome.is_complete());
        assert_eq!(
            store.coin(PurseId::MAIN, downstream).expect("exists").state,
            CoinState::Spent
        );
    }
}
