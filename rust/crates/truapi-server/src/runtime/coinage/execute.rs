//! Driving a planned operation against the chain.
//!
//! [`super::plan`] decides what to submit; this module submits it and grades what
//! came back. The order of the five steps per transaction is fixed by §7.4 and is
//! the whole reason a crash cannot lose value:
//!
//! 1. Mutate local state — outputs minted `Pending`, inputs already `LockedFor`.
//! 2. Write the log entry, including the extrinsic hash, and **persist**.
//! 3. Broadcast.
//! 4. On a definite outcome, apply it.
//! 5. On no definite outcome, hand the entry to recovery (§7.7).
//!
//! Step 2 comes before step 3 without exception. A hash recorded after the
//! broadcast would leave a crash in between with a transaction on chain that no
//! local record mentions, and nothing to reconcile it against.
//!
//! # The unload fee chooses the origin, not just an argument
//!
//! §6.6 reads like a choice between two ways to pay, but the two modes are
//! different *origins*. Prepaid means an unload token — a free slot from the
//! period's allowance, proven by personhood — and `max_fee` is zero. From-output
//! means no token at all: the extension takes the fee out of the unloaded value,
//! pre-validating the first entry's alias in its place, and `max_fee` is the
//! ceiling it may take. So an unfunded fee account does not merely change an
//! argument; it spends no allowance.
//!
//! Which means the fee has to be estimated before the origin is known. The
//! sequence is: assemble the prepaid shape, price *those exact bytes*, choose the
//! mode from the fee account's balance, and re-assemble if the answer was
//! from-output. Pricing real bytes rather than a guessed length is what keeps the
//! ceiling honest, and re-assembling costs proving time rather than value.

use core::time::Duration;

use futures_timer::Delay;
use truapi_platform::CoreStorage;

use crate::host_logic::coinage::derivation;
use crate::host_logic::coinage::error::CoinageError;
use crate::host_logic::coinage::event::LayerEvent;
use crate::host_logic::coinage::log::{Checkpoint, LogEntryState};
use crate::host_logic::coinage::memo::{MemoEntry, PaymentClassification};
use crate::host_logic::coinage::operation::{LockSet, OperationStatus};
use crate::host_logic::coinage::types::{
    BlockHash, CoinAccountId, CoinSecret, DenominationExponent, ExtrinsicHash, OperationHandle,
    PurseId, RingLocation, Timestamp,
};
use crate::host_logic::coinage::unload_token::{
    FeeMode, PaidRingState, TokenGrant, choose_fee_mode, resolve,
};
use crate::runtime::coinage::bootstrap::CoinageLayer;
use crate::runtime::coinage::call::{
    CoinOutput, LoadRecyclerWithCoinArgs, PayForUnloadFeeTokenArgs, RawEncoded, SplitArgs,
    TransferArgs, UnloadRecyclerIntoCoinsArgs,
};
use crate::runtime::coinage::extension::{AsCoinageInfo, FreeTokenRing};
use crate::runtime::coinage::extrinsic::{
    CoinageCall, FundingOrigin, build_account_signed_extrinsic, build_call,
    build_coin_origin_extrinsic, build_external_asset_load_extrinsic, build_unsigned_extrinsic,
    inherited_implication,
};
use crate::runtime::coinage::plan::{
    Destination, PlannedOutput, PlannedTransaction, RescueGroup, SweepWork, TargetDestinations,
    TransactionKind, plan_import, plan_maintenance, plan_operation,
};
use crate::runtime::coinage::{fee, proof, recover, ring, scan, storage, submit, tokens};
use crate::runtime::statement_allowance::bandersnatch_entropy;
use crate::runtime::statement_allowance::extension::{ChainState, Metadata};
use crate::runtime::statement_allowance::rpc::RpcClient;

/// How long to wait between recovery passes while a transaction's fate is open.
///
/// Roughly a block: shorter would re-read the same finalized state, longer would
/// keep an operation in `Recovering` after the chain had already answered.
const RECOVERY_POLL_INTERVAL: Duration = Duration::from_secs(6);

/// How many recovery passes to run before leaving the entry for the layer's own
/// recovery driver.
///
/// Bounded so a stalled chain cannot pin a caller forever. Giving up here is not
/// a verdict: the entry stays `Pending` in the log and the operation stays open,
/// which is exactly the state recovery resumes from at the next start (§7.7).
const RECOVERY_POLL_ATTEMPTS: usize = 40;

/// How many phases an external offload may go through before it is left for a
/// later drive.
///
/// Bounded so a chain that never ripens an entry cannot hold a caller forever.
/// Reaching the limit is not a failure: the operation stays open, and both recovery
/// and a later drive resume from where it stopped.
const OFFLOAD_PHASE_LIMIT: usize = 32;

/// Everything chain-facing an operation needs.
pub struct ChainContext<'a> {
    /// JSON-RPC surface.
    pub rpc: &'a RpcClient,
    /// Runtime metadata, for call indices, extension slots and value decoding.
    pub metadata: &'a Metadata,
    /// How long to wait between recovery passes.
    pub recovery_poll_interval: Duration,
}

impl<'a> ChainContext<'a> {
    /// A context with the default recovery cadence.
    pub fn new(rpc: &'a RpcClient, metadata: &'a Metadata) -> Self {
        Self {
            rpc,
            metadata,
            recovery_poll_interval: RECOVERY_POLL_INTERVAL,
        }
    }
}

/// What a caller supplies to be told, out of band, which coins a transfer minted.
///
/// Invoked once per transaction, with one entry per coin that transaction sent to
/// an account outside this layer, as soon as the transaction reaches a block —
/// deliberately before finalization, so a payee can act promptly. The cost of that
/// choice is real: a reorg can invalidate a transfer a memo has already been
/// delivered for, and the caller has to tolerate it.
pub type MemoCallback = Box<dyn Fn(Vec<MemoEntry>) + Send + Sync>;

/// Work an operation does locally once its transactions have definitely settled.
///
/// Kept beside the operation rather than inside its program because it is not a
/// transaction: nothing is broadcast for it, and it must not run until the chain
/// has agreed the value actually moved.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Completion {
    /// Tell subscribers what a maintenance sweep achieved (§6.4).
    ReportSweep {
        /// Coins turned into entries.
        coins_recycled: u32,
        /// Entries turned back into coins.
        entries_rescued: u32,
    },
    /// Close a drained purse, once its value has definitely left (§8.1).
    ClosePurse {
        /// Purse to close.
        target: PurseId,
        /// Where its value went.
        drained_into: PurseId,
        /// How much moved.
        amount: crate::host_logic::coinage::types::Amount,
    },
}

/// A started operation: its handle, and its status stream (§8, §7.2).
///
/// Returned the moment selection and locking have succeeded, before anything is
/// broadcast. That split is the spec's: a failure to *start* comes back as an
/// error from the starting call, while a failure of a started operation arrives as
/// a terminal `Failed` item on this stream.
#[derive(derive_more::Debug)]
pub struct OperationStart {
    /// Durable handle for the operation.
    pub handle: OperationHandle,
    /// Its status stream, opening with the current status.
    #[debug(skip)]
    pub status: futures::stream::BoxStream<'static, OperationStatus>,
}

impl CoinageLayer {
    /// Start a transfer from `purse` to recipient-controlled accounts (§8.3).
    ///
    /// Selects, locks and plans synchronously, so an unsatisfiable request fails
    /// here rather than on the status stream. Nothing is broadcast until
    /// [`CoinageLayer::drive_operation`] runs.
    ///
    /// The recipient outputs must sum to `amount`; each one is a separately named
    /// account, so the produced denominations are exactly those requested.
    ///
    /// `memo` is invoked as each transaction lands, per [`MemoCallback`].
    pub fn begin_transfer(
        &mut self,
        purse: PurseId,
        amount: crate::host_logic::coinage::types::Amount,
        recipient_outputs: Vec<CoinOutput>,
        allow_degraded: bool,
        memo: Option<MemoCallback>,
        now: Timestamp,
    ) -> Result<OperationStart, CoinageError> {
        use crate::host_logic::coinage::selection::{OutputRequirement, SelectionRequest};
        use crate::host_logic::coinage::types::{Amount, OperationKind};

        let requested: Amount = recipient_outputs
            .iter()
            .map(|output| output.exponent.value())
            .fold(Amount::ZERO, |total, value| {
                total.checked_add(value).unwrap_or(total)
            });
        if requested != amount {
            return Err(CoinageError::OutputsDoNotSumToAmount);
        }

        let request = SelectionRequest {
            amount,
            outputs: OutputRequirement::Exact(
                recipient_outputs
                    .iter()
                    .map(|output| output.exponent)
                    .collect(),
            ),
            allow_degraded,
        };

        let started = self.begin(
            purse,
            OperationKind::Transfer,
            &request,
            TargetDestinations::Recipients(recipient_outputs),
            now,
        )?;
        if let Some(memo) = memo {
            self.register_memo(started.handle, memo);
        }
        Ok(started)
    }

    /// Select, lock and plan one operation.
    ///
    /// Shared by every primitive that spends from a purse. Selection and locking
    /// happen in one step inside the store, so no other caller can see the window
    /// between choosing a record and holding it.
    pub(crate) fn begin(
        &mut self,
        purse: PurseId,
        kind: crate::host_logic::coinage::types::OperationKind,
        request: &crate::host_logic::coinage::selection::SelectionRequest,
        targets: TargetDestinations,
        now: Timestamp,
    ) -> Result<OperationStart, CoinageError> {
        let constants = *self.constants();
        let (handle, selection) = self
            .store_mut()
            .begin_operation(purse, kind, request, &constants, now)?;

        let program = match plan_operation(self.store_mut(), purse, &selection, &targets) {
            Ok(program) => program,
            Err(error) => {
                // Planning failed after the records were locked, so release them
                // before the caller sees the error: an operation nobody holds a
                // handle to must not keep value out of the pool.
                let _ = self.store_mut().fail_operation(handle, error.clone());
                return Err(error);
            }
        };

        let status = self.subscribe_operation_status(handle)?;
        self.register_program(handle, program);
        Ok(OperationStart { handle, status })
    }
}

/// One coin leaving the layer under its own secret (§8.4).
///
/// The only value in this crate that carries spendable key material outward. Once
/// emitted, the layer treats the coin as spent: the account still holds it on
/// chain, but control has moved to whoever holds this.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExportedCoin {
    /// Account holding the coin.
    pub account: CoinAccountId,
    /// Secret controlling it.
    pub secret: CoinSecret,
    /// Its denomination.
    pub exponent: DenominationExponent,
}

/// A started export: the operation, plus the coins it hands out (§8.4).
#[derive(derive_more::Debug)]
pub struct ExportStart {
    /// Durable handle for the operation.
    pub handle: OperationHandle,
    /// Its status stream, opening with the current status.
    #[debug(skip)]
    pub status: futures::stream::BoxStream<'static, OperationStatus>,
    /// One item per exported coin, then closed.
    ///
    /// A coin appears only once the transaction that materialized it has
    /// **definitely** succeeded, because a secret handed out on optimistic
    /// inclusion could name a coin a reorg then removes.
    #[debug(skip)]
    pub coins: futures::stream::BoxStream<'static, ExportedCoin>,
}

/// The layer seam: value leaving under its own secrets, and value arriving under
/// somebody else's (§8.4, §8.5).
impl CoinageLayer {
    /// Materialize `amount` worth of coins in `from` and hand them out (§8.4).
    ///
    /// Coins already in the right shape cost nothing: control of a coin changes
    /// hands with its secret, so an export that needs no reshaping submits no
    /// extrinsic at all. Value that has to be split or unloaded costs one
    /// transaction each, and those coins are emitted only once the chain has
    /// definitely accepted them.
    pub fn begin_export(
        &mut self,
        from: PurseId,
        amount: crate::host_logic::coinage::types::Amount,
        allow_degraded: bool,
        now: Timestamp,
    ) -> Result<ExportStart, CoinageError> {
        use crate::host_logic::coinage::selection::{OutputRequirement, SelectionRequest};
        use crate::host_logic::coinage::types::OperationKind;

        let request = SelectionRequest {
            amount,
            // The coins leave under their own secrets, so their shape is free.
            outputs: OutputRequirement::AnyDenominations,
            allow_degraded,
        };
        let started = self.begin(
            from,
            OperationKind::Export,
            &request,
            TargetDestinations::Export(from),
            now,
        )?;

        let (sender, receiver) = futures::channel::mpsc::unbounded();
        self.register_export(started.handle, sender);
        Ok(ExportStart {
            handle: started.handle,
            status: started.status,
            coins: Box::pin(receiver),
        })
    }

    /// Take externally held coins into `into` (§8.5).
    ///
    /// Each coin's denomination is read from chain rather than taken on trust, and
    /// each pair is checked before anything is planned: a secret that does not
    /// control the account it is offered with, or a coin this layer already holds a
    /// record for, is refused with `BadCoinSecret`. Reading the denomination is why
    /// this is the one starting call that touches the chain.
    ///
    /// One transaction per coin, all independent, so partial success is normal.
    pub async fn begin_import(
        &mut self,
        chain: &ChainContext<'_>,
        into: PurseId,
        coins: Vec<(CoinAccountId, CoinSecret)>,
    ) -> Result<OperationStart, CoinageError> {
        use crate::host_logic::coinage::types::OperationKind;

        if self.store().purse(into).is_none() {
            return Err(CoinageError::PurseNotFound(into));
        }

        let at = chain
            .rpc
            .finalized_head()
            .await
            .map_err(|error| CoinageError::SubscriptionError(error.to_string()))?;

        let mut described = Vec::with_capacity(coins.len());
        for (account, secret) in &coins {
            // A secret that does not control the account cannot move its coin, and
            // finding that out here costs nothing.
            if keypair_from(secret)?.public.to_bytes() != account.0 {
                return Err(CoinageError::BadCoinSecret);
            }
            // A coin we already have a record for must not be imported: it would
            // get a second record, and one of the two would be a ghost.
            if self.holds_account(*account) {
                return Err(CoinageError::BadCoinSecret);
            }

            let raw = chain
                .rpc
                .get_storage_at(&storage::coins_by_owner_key(account), &at)
                .await
                .map_err(|error| CoinageError::SubscriptionError(error.to_string()))?;
            let coin = storage::decode_coin(raw)?.ok_or(CoinageError::BadCoinSecret)?;
            let exponent = DenominationExponent::new(coin.value).ok_or_else(|| {
                CoinageError::Internal(format!(
                    "the chain reports denomination {} for an imported coin, which this layer \
                     cannot represent",
                    coin.value
                ))
            })?;
            described.push((*account, exponent));
        }

        let handle = self
            .store_mut()
            .start_operation(into, OperationKind::Import)?;
        let program = match plan_import(self.store_mut(), into, &described) {
            Ok(program) => program,
            Err(error) => {
                let _ = self.store_mut().fail_operation(handle, error.clone());
                return Err(error);
            }
        };

        let status = self.subscribe_operation_status(handle)?;
        self.register_import_secrets(
            handle,
            coins.into_iter().map(|(_, secret)| secret).collect(),
        );
        self.register_program(handle, program);
        Ok(OperationStart { handle, status })
    }

    /// Whether any record in any purse already names this account.
    fn holds_account(&self, account: CoinAccountId) -> bool {
        self.store().purses().any(|purse| {
            self.store().coins_in(purse.id).into_iter().any(|coin| {
                derivation::coin_account_id(self.entropy(), purse.id, coin.index)
                    .is_ok_and(|derived| derived == account)
            })
        })
    }

    /// Hand out the coins a settled transaction materialized for export.
    fn deliver_exports(
        &mut self,
        handle: OperationHandle,
        exports: &[(PurseId, crate::host_logic::coinage::types::CoinIndex)],
    ) -> Result<(), CoinageError> {
        if exports.is_empty() {
            return Ok(());
        }

        let mut emitted = Vec::with_capacity(exports.len());
        for (purse, index) in exports {
            let exponent = self
                .store()
                .coin(*purse, *index)
                .ok_or_else(|| {
                    CoinageError::Internal(format!("exported coin {index:?} has no record"))
                })?
                .exponent;
            let keypair = derivation::coin_keypair(self.entropy(), *purse, *index)?;
            emitted.push((
                *purse,
                *index,
                ExportedCoin {
                    account: CoinAccountId(keypair.public.to_bytes()),
                    secret: CoinSecret(keypair.secret.to_bytes()),
                    exponent,
                },
            ));
        }

        for (purse, index, coin) in emitted {
            // Spent from this layer's point of view the moment the secret leaves:
            // the account still holds the coin, but we no longer control it, and
            // offering it to selection again would build an extrinsic the chain
            // refuses.
            self.store_mut().retire_exported(purse, index, handle)?;
            self.send_export(handle, coin);
        }

        Ok(())
    }
}

/// The keypair a supplied secret controls.
fn keypair_from(secret: &CoinSecret) -> Result<schnorrkel::Keypair, CoinageError> {
    let parsed = crate::host_logic::extrinsic::sr25519_secret_from_bytes(&secret.0)
        .map_err(|_| CoinageError::BadCoinSecret)?;
    let public = parsed.to_public();
    Ok(schnorrkel::Keypair {
        secret: parsed,
        public,
    })
}

/// What an external offload was asked to do (§8.6).
///
/// Held for the operation's whole life because the offload re-plans: the amount and
/// the destination are the only things that stay fixed across its phases.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OffloadRequest {
    /// Purse the value comes from.
    pub from: PurseId,
    /// Amount to deliver.
    pub amount: crate::host_logic::coinage::types::Amount,
    /// Account outside coinage that receives it.
    pub destination: CoinAccountId,
    /// Whether entries below the anonymity floor may be used.
    pub allow_degraded: bool,
}

/// External offload (§8.6): value leaving coinage for an ordinary account.
///
/// The only multi-phase primitive. Coins cannot be offboarded — a coin has to
/// become an entry first — and a fresh entry is not usable until its decorrelation
/// delay elapses, so the operation loops: work out what is possible now, do that,
/// look again. [`crate::host_logic::coinage::offload::decide`] is the "look again"
/// step and is pure; this is the part that submits, waits and persists.
impl CoinageLayer {
    /// Start an offload of `amount` from `from` to `destination` (§8.6).
    ///
    /// `allow_degraded` should be false unless the caller means it: an offload
    /// reveals the unloaded value to anyone watching the chain, so the anonymity set
    /// wants to be at full strength.
    ///
    /// Nothing is selected here. The operation holds records as it acquires them,
    /// which is what lets it use entries it created itself in a later phase.
    pub fn begin_external_offload(
        &mut self,
        from: PurseId,
        amount: crate::host_logic::coinage::types::Amount,
        destination: CoinAccountId,
        allow_degraded: bool,
    ) -> Result<OperationStart, CoinageError> {
        use crate::host_logic::coinage::types::OperationKind;

        if self.store().purse(from).is_none() {
            return Err(CoinageError::PurseNotFound(from));
        }

        let handle = self
            .store_mut()
            .start_operation(from, OperationKind::ExternalOffload)?;
        let status = self.subscribe_operation_status(handle)?;
        self.register_offload(
            handle,
            OffloadRequest {
                from,
                amount,
                destination,
                allow_degraded,
            },
        );
        Ok(OperationStart { handle, status })
    }

    /// Drive an offload through as many phases as it takes.
    ///
    /// Every phase transition is persisted before the next begins, so a crash
    /// resumes from the last one rather than from the start. The loop is bounded:
    /// a chain that never ripens an entry must not hold a caller forever, and an
    /// operation left open is exactly what recovery resumes.
    async fn drive_offload<S: CoreStorage + ?Sized>(
        &mut self,
        storage: &S,
        chain: &ChainContext<'_>,
        handle: OperationHandle,
        request: OffloadRequest,
        now: Timestamp,
    ) -> Result<(), CoinageError> {
        use crate::host_logic::coinage::offload::{OffloadPhase, decide};

        let mut clock = now;
        let mut recycle_sequences: Vec<u32> = Vec::new();
        let mut settlements = Vec::new();

        for _ in 0..OFFLOAD_PHASE_LIMIT {
            self.advance(storage, handle, OperationStatus::Preparing, clock)
                .await?;

            // §8.6 step 1 reads the *current* view, and it has to be a chain read:
            // an entry a previous phase created knows nothing about the ring the
            // pallet put it in, and an entry with no ring cannot be offboarded. A
            // loop that re-planned from local state alone would recycle forever.
            self.refresh_purse(storage, chain, request.from, clock)
                .await?;

            let phase = decide(
                &self.store().coins_in(request.from),
                &self.store().entries_in(request.from),
                request.amount,
                request.allow_degraded,
                self.constants(),
                self.params().external_offload_retry_interval,
                clock,
                handle,
            );

            match phase {
                OffloadPhase::Offboard { groups, surplus } => {
                    let outcome = self
                        .run_offboard(
                            storage,
                            chain,
                            handle,
                            &request,
                            &groups,
                            surplus,
                            &recycle_sequences,
                            clock,
                        )
                        .await?;
                    settlements.extend(outcome);
                    return self.terminate(storage, handle, &settlements, clock).await;
                }
                OffloadPhase::Recycle { coins } => {
                    let outcome = self
                        .run_offload_recycles(storage, chain, handle, &request, &coins, clock)
                        .await?;
                    settlements.extend(outcome.settlements);
                    recycle_sequences.extend(outcome.sequences);
                    if settlements.contains(&Settlement::Undecided) {
                        // A transaction whose fate is open must not be re-planned
                        // around: recovery owns it now.
                        return self.terminate(storage, handle, &settlements, clock).await;
                    }
                }
                OffloadPhase::Wait { until, .. } => {
                    self.advance(storage, handle, OperationStatus::Waiting(until), clock)
                        .await?;
                    Delay::new(chain.recovery_poll_interval).await;
                    // The layer holds no clock, so a waiting phase advances the one
                    // it was given rather than reading a new one.
                    clock = until.max(clock);
                }
                OffloadPhase::Insufficient {
                    requested,
                    available,
                } => {
                    self.store_mut().fail_operation(
                        handle,
                        CoinageError::InsufficientFunds {
                            requested,
                            available,
                        },
                    )?;
                    return self.publish_and_persist(storage, clock).await;
                }
            }
        }

        // Out of phases rather than out of options: leave the operation open, which
        // is the state recovery and a later drive both resume from.
        self.publish_and_persist(storage, clock).await
    }

    /// Re-read one purse's chain state and apply it (§6.1).
    ///
    /// Pinned to the finalized head: a phase decision taken against a fork that
    /// then disappears would plan an offboard of entries that are not there.
    async fn refresh_purse<S: CoreStorage + ?Sized>(
        &mut self,
        storage: &S,
        chain: &ChainContext<'_>,
        purse: PurseId,
        now: Timestamp,
    ) -> Result<(), CoinageError> {
        let at = chain
            .rpc
            .finalized_head()
            .await
            .map_err(|error| CoinageError::SubscriptionError(error.to_string()))?;
        let entropy = self.entropy().to_vec();
        let params = self.params().clone();
        crate::runtime::coinage::observe::refresh_purse(
            chain.rpc,
            chain.metadata,
            self.store_mut(),
            &entropy,
            purse,
            &params,
            &at,
        )
        .await?;
        self.publish_and_persist(storage, now).await
    }

    /// Recycle coins into entries this offload will offboard.
    async fn run_offload_recycles<S: CoreStorage + ?Sized>(
        &mut self,
        storage: &S,
        chain: &ChainContext<'_>,
        handle: OperationHandle,
        request: &OffloadRequest,
        coins: &[(
            crate::host_logic::coinage::types::CoinIndex,
            DenominationExponent,
        )],
        now: Timestamp,
    ) -> Result<RecyclePass, CoinageError> {
        let jitter = self.jitter_draws(coins.len())?;
        let mut pass = RecyclePass::default();

        for ((coin, exponent), delay) in coins.iter().zip(jitter) {
            let locks = LockSet {
                coins: vec![(request.from, *coin)],
                entries: Vec::new(),
            };
            self.store_mut().lock_for_operation(handle, &locks, now)?;
            let entry = self
                .store_mut()
                .allocate_entry(request.from, *exponent, now, delay)?;
            self.store_mut().lock_for_operation(
                handle,
                &LockSet {
                    coins: Vec::new(),
                    entries: vec![(request.from, entry)],
                },
                now,
            )?;

            let transaction = PlannedTransaction {
                kind: TransactionKind::Recycle {
                    source: (request.from, *coin),
                    entry: (request.from, entry),
                },
                inputs: locks,
                outputs: LockSet {
                    coins: Vec::new(),
                    entries: vec![(request.from, entry)],
                },
                depends_on: Vec::new(),
                exports: Vec::new(),
            };

            let sequence = self.next_sequence(handle);
            let settlement = self
                .run_transaction(storage, chain, handle, &transaction, &mut Vec::new(), now)
                .await?;
            if settlement == Settlement::Succeeded {
                pass.sequences.push(sequence);
            }
            pass.settlements.push(settlement);
        }

        Ok(pass)
    }

    /// Offboard the groups that cover the requested amount.
    ///
    /// Each group is one extrinsic carrying one token, and each carries its own
    /// share of the payout plus vouchers for whatever it overshoots by.
    #[allow(clippy::too_many_arguments)]
    async fn run_offboard<S: CoreStorage + ?Sized>(
        &mut self,
        storage: &S,
        chain: &ChainContext<'_>,
        handle: OperationHandle,
        request: &OffloadRequest,
        groups: &[crate::host_logic::coinage::offload::OffboardGroup],
        surplus: crate::host_logic::coinage::types::Amount,
        depends_on: &[u32],
        now: Timestamp,
    ) -> Result<Vec<Settlement>, CoinageError> {
        use crate::host_logic::coinage::params::canonical_breakdown;
        use crate::host_logic::coinage::types::Amount;

        let mut grants = self.offload_tokens(chain, groups.len(), now).await?;
        let mut settlements = Vec::new();
        let mut remaining_payout = request.amount;
        let mut remaining_surplus = surplus;

        for group in groups {
            // Each group pays out what it can of the outstanding amount and keeps
            // the rest as vouchers, so the arithmetic balances per extrinsic —
            // which is how the pallet checks it.
            let group_value = group.value();
            let payout = group_value.min(remaining_payout);
            let reload = group_value.saturating_sub(payout);
            remaining_payout = remaining_payout.saturating_sub(payout);
            remaining_surplus = remaining_surplus.saturating_sub(reload);

            let denominations = if reload.is_zero() {
                Vec::new()
            } else {
                canonical_breakdown(
                    reload,
                    self.constants().largest_denomination().ok_or_else(|| {
                        CoinageError::Internal(
                            "the runtime's maximum exponent is not a denomination".to_string(),
                        )
                    })?,
                )
                .ok_or(CoinageError::UnsatisfiableOutputs {
                    requested: reload,
                    available: group_value,
                })?
            };

            // The surplus becomes entries of ours, so it needs records and locks
            // like anything else the operation holds.
            let mut vouchers = Vec::with_capacity(denominations.len());
            for exponent in &denominations {
                let entry = self.store_mut().allocate_entry(
                    request.from,
                    *exponent,
                    now,
                    core::time::Duration::ZERO,
                )?;
                self.store_mut().lock_for_operation(
                    handle,
                    &LockSet {
                        coins: Vec::new(),
                        entries: vec![(request.from, entry)],
                    },
                    now,
                )?;
                vouchers.push((*exponent, entry));
            }

            self.store_mut().lock_for_operation(
                handle,
                &LockSet {
                    coins: Vec::new(),
                    entries: group.entries.iter().map(|e| (request.from, *e)).collect(),
                },
                now,
            )?;

            let transaction = PlannedTransaction {
                kind: TransactionKind::Offboard {
                    purse: request.from,
                    ring: group.ring,
                    exponent: group.exponent,
                    entries: group.entries.clone(),
                    destination: request.destination,
                    payout,
                    vouchers: vouchers.clone(),
                },
                inputs: LockSet {
                    coins: Vec::new(),
                    entries: group.entries.iter().map(|e| (request.from, *e)).collect(),
                },
                outputs: LockSet {
                    coins: Vec::new(),
                    entries: vouchers
                        .iter()
                        .map(|(_, entry)| (request.from, *entry))
                        .collect(),
                },
                // §7.5: the entries this offboard spends may be ones an earlier
                // recycle produced, and recovery has to resolve them in that order.
                depends_on: depends_on.to_vec(),
                exports: Vec::new(),
            };

            settlements.push(
                self.run_transaction(storage, chain, handle, &transaction, &mut grants, now)
                    .await?,
            );
        }

        let _ = Amount::ZERO;
        Ok(settlements)
    }

    /// Tokens for an offboard's groups, one each.
    async fn offload_tokens(
        &self,
        chain: &ChainContext<'_>,
        groups: usize,
        now: Timestamp,
    ) -> Result<Vec<TokenGrant>, CoinageError> {
        if groups == 0 {
            return Ok(Vec::new());
        }
        let program = crate::runtime::coinage::plan::OperationProgram {
            transactions: Vec::new(),
            exports_in_place: Vec::new(),
        };
        let _ = &program;
        self.resolve_tokens(chain, groups, now).await
    }

    /// The sequence the next log entry of this operation will take.
    fn next_sequence(&self, handle: OperationHandle) -> u32 {
        self.store()
            .operation(handle)
            .map_or(0, |operation| operation.log.next_sequence())
    }
}

/// What one recycle phase settled, and which sequences succeeded.
#[derive(Debug, Default)]
struct RecyclePass {
    settlements: Vec<Settlement>,
    sequences: Vec<u32>,
}

/// Top-up: external asset in, recycler entries out (§8.2).
impl CoinageLayer {
    /// Convert `amount` of externally held asset into entries in `into` (§8.2).
    ///
    /// The value being converted is not coinage yet, so the layer neither holds nor
    /// signs for it: `origin` owns the account and signs the extrinsic. What the
    /// layer contributes is the entries — fresh member keys in `into`'s namespace,
    /// each proving to the pallet that whoever controls the incoming value controls
    /// the key it is being loaded onto.
    ///
    /// The amount is broken into denominations the runtime mints, and the whole
    /// top-up is one batched extrinsic, bounded by `MaxBatchUnpaidLoad`.
    pub fn begin_top_up(
        &mut self,
        into: PurseId,
        amount: crate::host_logic::coinage::types::Amount,
        origin: std::sync::Arc<dyn FundingOrigin + Send + Sync>,
        now: Timestamp,
    ) -> Result<OperationStart, CoinageError> {
        use crate::host_logic::coinage::params::canonical_breakdown;
        use crate::host_logic::coinage::types::OperationKind;

        if self.store().purse(into).is_none() {
            return Err(CoinageError::PurseNotFound(into));
        }

        let largest = self.constants().largest_denomination().ok_or_else(|| {
            CoinageError::Internal(
                "the runtime's maximum exponent is not a denomination".to_string(),
            )
        })?;
        let denominations =
            canonical_breakdown(amount, largest).ok_or(CoinageError::UnsatisfiableOutputs {
                requested: amount,
                available: amount,
            })?;
        let batch_limit = self.constants().max_batch_unpaid_load as usize;
        if denominations.len() > batch_limit {
            return Err(CoinageError::Internal(format!(
                "{amount} needs {} entries but the runtime batches at most {batch_limit}",
                denominations.len()
            )));
        }

        let handle = self
            .store_mut()
            .start_operation(into, OperationKind::TopUp)?;

        // Each entry gets its own decorrelation delay, drawn now: an entry that
        // became selectable the instant it was loaded would let an observer pair
        // the load with the unload that follows it.
        let jitter = self.jitter_draws(denominations.len())?;
        let mut entries = Vec::with_capacity(denominations.len());
        for (exponent, delay) in denominations.iter().zip(jitter) {
            match self.store_mut().allocate_entry(into, *exponent, now, delay) {
                Ok(index) => entries.push((*exponent, index)),
                Err(error) => {
                    let _ = self.store_mut().fail_operation(handle, error.clone());
                    return Err(error);
                }
            }
        }

        let program = crate::runtime::coinage::plan::OperationProgram {
            transactions: vec![PlannedTransaction {
                kind: TransactionKind::TopUpLoad {
                    purse: into,
                    entries: entries.clone(),
                },
                // Nothing of ours is consumed: the input is the caller's asset.
                inputs: LockSet::default(),
                outputs: LockSet {
                    coins: Vec::new(),
                    entries: entries.iter().map(|(_, index)| (into, *index)).collect(),
                },
                depends_on: Vec::new(),
                exports: Vec::new(),
            }],
            exports_in_place: Vec::new(),
        };

        let status = self.subscribe_operation_status(handle)?;
        self.register_funding_origin(handle, origin);
        self.register_program(handle, program);
        Ok(OperationStart { handle, status })
    }

    /// Assemble the batched load, signed by the account holding the asset.
    async fn assemble_top_up(
        &self,
        chain: &ChainContext<'_>,
        state: &ChainState,
        purse: PurseId,
        entries: &[(
            DenominationExponent,
            crate::host_logic::coinage::types::EntryIndex,
        )],
        origin: &dyn FundingOrigin,
    ) -> Result<Assembled, CoinageError> {
        use crate::runtime::coinage::call::UnpaidLoadBatchArgs;

        let account = origin.external_account();
        let mut items = Vec::with_capacity(entries.len());
        for (exponent, index) in entries {
            let member_key = derivation::entry_member_key(self.entropy(), purse, *index)?;
            // The proof binds the key to the account whose asset is being
            // converted, which is what stops one wallet loading onto another's key.
            let ownership = proof::entry_ownership_proof(self.entropy(), purse, *index, account)?;
            items.push((*exponent, member_key, ownership));
        }

        let args = UnpaidLoadBatchArgs::new(items, self.constants())?;
        let call = build_call(
            chain.metadata,
            CoinageCall::LoadRecyclerWithExternalAssetUnpaidBatch,
            &args,
        )?;
        let nonce = read_account_nonce(chain.rpc, account).await?;

        Ok(Assembled {
            extrinsic: build_external_asset_load_extrinsic(
                chain.metadata,
                state,
                origin,
                nonce,
                &call,
            )?,
            event: None,
            origins: vec![account],
        })
    }
}

/// The next transaction index the chain expects from an account.
///
/// Read rather than tracked: the account is the caller's, and anything else may
/// have used it since.
async fn read_account_nonce(rpc: &RpcClient, account: CoinAccountId) -> Result<u32, CoinageError> {
    let address = subxt::utils::AccountId32(account.0).to_string();
    let value = rpc
        .call("system_accountNextIndex", serde_json::json!([address]))
        .await
        .map_err(|error| CoinageError::SubscriptionError(error.to_string()))?;

    value
        .as_u64()
        .and_then(|nonce| u32::try_from(nonce).ok())
        .ok_or_else(|| CoinageError::Internal(format!("system_accountNextIndex returned {value}")))
}

/// What a wallet-recovery scan was asked to walk (§8.10).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RecoveryRequest {
    /// Purses to scan, with the index each sub-tree starts from.
    pub purses: Vec<(
        PurseId,
        crate::host_logic::coinage::types::CoinIndex,
        crate::host_logic::coinage::types::EntryIndex,
    )>,
}

/// Wallet recovery from root entropy (§8.10, Appendix C).
///
/// The other kind of recovery: §7.7 resolves transactions that were in flight when
/// a process died, while this rebuilds records that are gone entirely. It submits
/// nothing — every answer comes from the chain — so its status goes straight from
/// `Preparing` to a terminal item, and what it found arrives on the event stream
/// record by record.
impl CoinageLayer {
    /// Rebuild the main purse and the listed purses from chain (§8.10).
    ///
    /// The chain has no notion of a purse, so a non-main purse is only found if its
    /// identifier is supplied from a backup — and it is restored *at* that
    /// identifier, because that is the derivation namespace its accounts are
    /// already in.
    pub fn begin_recovery(
        &mut self,
        non_main_purse_ids: Vec<PurseId>,
    ) -> Result<OperationStart, CoinageError> {
        use crate::host_logic::coinage::types::{CoinIndex, EntryIndex, OperationKind};

        let mut purses = vec![(PurseId::MAIN, CoinIndex(0), EntryIndex(0))];
        for purse in non_main_purse_ids {
            if purse.is_main() {
                continue;
            }
            // Restored rather than created: a fresh identifier would derive a
            // namespace nobody has coins in.
            self.store_mut()
                .restore_purse(purse, format!("Recovered {purse}"));
            purses.push((purse, CoinIndex(0), EntryIndex(0)));
        }

        let handle = self
            .store_mut()
            .start_operation(PurseId::MAIN, OperationKind::Recover)?;
        let status = self.subscribe_operation_status(handle)?;
        self.register_recovery(handle, RecoveryRequest { purses });
        Ok(OperationStart { handle, status })
    }

    /// Resume a scan past where a previous one stopped (§8.10).
    ///
    /// A scan ends after enough consecutive empty batches, which is the only way to
    /// terminate a walk over an unbounded index space — and it means a wallet with a
    /// long unused stretch can hide records beyond it. This is how a caller who
    /// knows better says so.
    pub fn begin_extend_scan(
        &mut self,
        purse: PurseId,
        from_coin_index: crate::host_logic::coinage::types::CoinIndex,
        from_entry_index: crate::host_logic::coinage::types::EntryIndex,
    ) -> Result<OperationStart, CoinageError> {
        use crate::host_logic::coinage::types::OperationKind;

        if self.store().purse(purse).is_none() {
            return Err(CoinageError::PurseNotFound(purse));
        }

        let handle = self
            .store_mut()
            .start_operation(purse, OperationKind::Recover)?;
        let status = self.subscribe_operation_status(handle)?;
        self.register_recovery(
            handle,
            RecoveryRequest {
                purses: vec![(purse, from_coin_index, from_entry_index)],
            },
        );
        Ok(OperationStart { handle, status })
    }

    /// Walk every purse the request names, then observe what was found.
    async fn drive_recovery<S: CoreStorage + ?Sized>(
        &mut self,
        storage: &S,
        chain: &ChainContext<'_>,
        handle: OperationHandle,
        request: RecoveryRequest,
        now: Timestamp,
    ) -> Result<(), CoinageError> {
        // One block for the whole scan: a walk spanning blocks could see a coin
        // move mid-way and record it twice, or not at all.
        let at = chain
            .rpc
            .finalized_head()
            .await
            .map_err(|error| CoinageError::SubscriptionError(error.to_string()))?;

        let mut found_anything = false;
        for (purse, from_coin, from_entry) in &request.purses {
            let params = self.params().clone();
            let entropy = self.entropy().to_vec();
            let outcome = match scan::scan_purse(
                chain.rpc,
                self.store_mut(),
                &entropy,
                *purse,
                &params,
                *from_coin,
                *from_entry,
                now,
                &at,
            )
            .await
            {
                Ok(outcome) => outcome,
                Err(error) => {
                    // A scan that cannot finish must not leave a half-rebuilt
                    // wallet looking complete.
                    self.store_mut()
                        .fail_operation(handle, CoinageError::RecoveryFailed(error.to_string()))?;
                    return self.publish_and_persist(storage, now).await;
                }
            };
            found_anything |= !outcome.is_empty();

            // Restored records know only that they exist. Their ring, their age
            // and any chain lock come from ordinary observation, which is the same
            // path a live wallet uses.
            if !outcome.is_empty() {
                crate::runtime::coinage::observe::refresh_purse(
                    chain.rpc,
                    chain.metadata,
                    self.store_mut(),
                    &entropy,
                    *purse,
                    &params,
                    &at,
                )
                .await?;
            }
        }

        let _ = found_anything;
        // Reconstruction is over; everything after `Resynced` is a live change.
        self.store_mut().publish(LayerEvent::Resynced);
        self.store_mut()
            .conclude_operation(handle, Default::default())?;
        self.publish_and_persist(storage, now).await
    }
}

/// Payment classification (§8.8).
impl CoinageLayer {
    /// Say how much of an incoming payment this layer can already see (§8.8).
    ///
    /// Synchronous, against the live local view: no chain read, no operation, no
    /// record touched. A payee runs this on the memo a payer sent to decide whether
    /// the coins it names have arrived.
    ///
    /// Matching is by account, not by amount. The coins a transfer mints land in
    /// accounts the payee named, so the question "is this mine?" is answered by
    /// deriving our own accounts and looking for the ones the memo names — which
    /// also means a memo cannot make the layer believe in value it does not hold.
    ///
    /// An empty entry list is `Unmatched`: nothing was claimed, so nothing matches.
    pub fn classify_incoming_payment(&self, entries: &[MemoEntry]) -> PaymentClassification {
        let matched = entries
            .iter()
            .filter(|entry| self.holds_account(entry.recipient_account))
            .count();

        match matched {
            0 => PaymentClassification::Unmatched,
            found if found == entries.len() => PaymentClassification::Matched,
            _ => PaymentClassification::Received,
        }
    }
}

/// What one [`CoinageLayer::tick`] did, and when it wants waking again.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TickOutcome {
    /// Whether a maintenance sweep ran. False means nothing was due — which is
    /// **not** evidence that nothing is at risk; see
    /// [`CoinageLayer::begin_maintenance_sweep`].
    pub swept: bool,
    /// How long the host may wait before calling again without letting a deadline
    /// pass. Advice about sufficient frequency, not a minimum gap.
    pub next_tick_after: Duration,
}

/// Autonomous lifecycle maintenance (§6.4, §8.7).
///
/// Two sweeps that together form a closed loop: coin to entry as coins age, entry
/// to coin as rings approach expiry. An unspent coin cycles between the two forms
/// indefinitely and keeps its value, so long as both run.
///
/// The layer has no clock outside a live session, so neither sweep fires by itself.
/// A host that embeds this layer has to tick it through [`CoinageLayer::tick`]; the
/// mechanism that does the ticking is truapi#356. A foreground-only trigger narrows
/// the loss window without closing it, because the failure mode is precisely "the
/// user did not open the app".
impl CoinageLayer {
    /// Do whatever is due at `now`, and say when the layer next wants waking.
    ///
    /// The core-side half of the invocation-lifecycle contract (truapi#356): the
    /// core owns *what* runs and *how*, the host owns only *when*. A host that calls
    /// this on a timer gets the whole of §6.4's autonomous behaviour; a host that
    /// never calls it gets a wallet that silently loses value once a recycler ring
    /// expires, which is the failure this exists to prevent.
    ///
    /// Two things happen, in this order:
    ///
    /// 1. **Balance streams are reprojected.** A jitter delay elapsing or a chain
    ///    lock expiring moves a purse's spendable balance with no record changing,
    ///    so nothing but the clock can surface it. Cheap and unconditional.
    /// 2. **Both sweeps run if anything is due**, as one operation which this drives
    ///    to completion before returning.
    ///
    /// # Scheduling needs no persisted state
    ///
    /// The sweeps decide what to do from the records themselves — a coin's age, an
    /// entry's ring deadline — not from how long it has been since the last run. So
    /// this is safe to call at any frequency: too often costs one pass over local
    /// records and returns nothing, and a restart loses no scheduling state because
    /// there is none to lose. The returned interval is advice about *sufficient*
    /// frequency, not a minimum gap the host must respect.
    ///
    /// # What it cannot do
    ///
    /// It cannot wait. There is no sleep or timer inside the core, which is why
    /// anything needing a second look — a paid unload token bought but not yet
    /// onboarded — is reported rather than waited on, and picked up by the next tick.
    pub async fn tick<S: CoreStorage + ?Sized>(
        &mut self,
        storage: &S,
        chain: &ChainContext<'_>,
        now: Timestamp,
    ) -> Result<TickOutcome, CoinageError> {
        self.refresh_subscriptions(now);

        let started = self.begin_maintenance_sweep(None, now)?;
        let swept = match started {
            None => false,
            Some(start) => {
                self.drive_operation(storage, chain, start.handle, now)
                    .await?;
                true
            }
        };

        Ok(TickOutcome {
            swept,
            next_tick_after: self.params().sweep_tick_interval(),
        })
    }

    /// Run both sweeps once across `purses`, or across every purse (§8.7).
    ///
    /// Returns `None` when there is nothing to do, so a scheduled tick that finds a
    /// tidy wallet costs no operation record and no event.
    ///
    /// **An empty result is not evidence that observation ran.** The rescue side
    /// reads each entry's own record of when its ring became immutable, and an
    /// entry nobody has observed has no deadline recorded — which looks exactly like
    /// a ring that is still accepting members. A caller that treats "nothing to
    /// rescue" as "nothing is at risk" reintroduces the loss it is trying to
    /// prevent.
    pub fn begin_maintenance_sweep(
        &mut self,
        purses: Option<Vec<PurseId>>,
        now: Timestamp,
    ) -> Result<Option<OperationStart>, CoinageError> {
        use crate::host_logic::coinage::types::OperationKind;

        let purses = match purses {
            Some(listed) => {
                for purse in &listed {
                    if self.store().purse(*purse).is_none() {
                        return Err(CoinageError::PurseNotFound(*purse));
                    }
                }
                listed
            }
            None => self.store().purses().map(|purse| purse.id).collect(),
        };

        let work = self.sweep_work(&purses, now);
        if work.is_empty() {
            return Ok(None);
        }

        let locks = sweep_locks(&work);
        let jitter = self.jitter_draws(work.iter().map(|item| item.aging_coins.len()).sum())?;

        // A sweep spans purses, so its operation is attributed to the first purse
        // with work; the lock set is what actually scopes it.
        let owner = work[0].purse;
        let handle = self
            .store_mut()
            .start_operation(owner, OperationKind::MaintenanceSweep)?;
        self.store_mut()
            .publish(LayerEvent::MaintenanceSweepStarted {
                purses: work.iter().map(|item| item.purse).collect(),
            });

        if let Err(error) = self.store_mut().lock_for_operation(handle, &locks, now) {
            let _ = self.store_mut().fail_operation(handle, error.clone());
            return Err(error);
        }
        let program = match plan_maintenance(self.store_mut(), &work, now, &jitter) {
            Ok(program) => program,
            Err(error) => {
                let _ = self.store_mut().fail_operation(handle, error.clone());
                return Err(error);
            }
        };

        let status = self.subscribe_operation_status(handle)?;
        self.register_completion(
            handle,
            Completion::ReportSweep {
                coins_recycled: work.iter().map(|item| item.aging_coins.len() as u32).sum(),
                entries_rescued: work
                    .iter()
                    .flat_map(|item| item.rescues.iter())
                    .map(|group| group.entries.len() as u32)
                    .sum(),
            },
        );
        self.register_program(handle, program);
        Ok(Some(OperationStart { handle, status }))
    }

    /// What both sweeps have to do, per purse.
    fn sweep_work(&self, purses: &[PurseId], now: Timestamp) -> Vec<SweepWork> {
        let recycle_at = self.constants().recycle_at_age();
        let margin = self
            .params()
            .rescue_margin(self.constants().recycler_expiration_time);

        purses
            .iter()
            .filter_map(|purse| {
                let aging_coins: Vec<_> = self
                    .store()
                    .coins_needing_recycling(*purse, recycle_at, now)
                    .into_iter()
                    .filter_map(|index| {
                        self.store()
                            .coin(*purse, index)
                            .map(|coin| (index, coin.exponent))
                    })
                    .collect();
                let rescues = self.rescue_groups(*purse, margin, now);

                (!aging_coins.is_empty() || !rescues.is_empty()).then_some(SweepWork {
                    purse: *purse,
                    aging_coins,
                    rescues,
                })
            })
            .collect()
    }

    /// Entries due for rescue, bucketed the way they will be unloaded.
    ///
    /// One extrinsic per `(denomination, ring)` bucket, each carrying its own token,
    /// and each bucket bounded by what the runtime consolidates.
    fn rescue_groups(
        &self,
        purse: PurseId,
        margin: core::time::Duration,
        now: Timestamp,
    ) -> Vec<RescueGroup> {
        let due = self.store().entries_needing_rescue(
            purse,
            self.constants().recycler_expiration_time,
            margin,
            now,
        );

        let cap = self.constants().max_consolidation.max(1) as usize;
        let mut buckets: Vec<RescueGroup> = Vec::new();
        for index in due {
            let Some(entry) = self.store().entry(purse, index) else {
                continue;
            };
            let Some(ring) = entry.ring else {
                continue;
            };

            match buckets.iter_mut().find(|group| {
                group.ring == ring && group.exponent == entry.exponent && group.entries.len() < cap
            }) {
                Some(group) => group.entries.push(index),
                None => buckets.push(RescueGroup {
                    ring,
                    exponent: entry.exponent,
                    entries: vec![index],
                }),
            }
        }

        buckets
    }

    /// One readiness delay per coin being recycled.
    ///
    /// Random by requirement, not by taste: a new entry that became selectable the
    /// instant it was loaded would let an observer pair the load with the unload
    /// that follows it (§5.3).
    fn jitter_draws(&self, count: usize) -> Result<Vec<core::time::Duration>, CoinageError> {
        let bound = self.params().recycler_entry_jitter_upper_bound;
        if bound.is_zero() {
            return Ok(vec![core::time::Duration::ZERO; count]);
        }

        let mut draws = Vec::with_capacity(count);
        for _ in 0..count {
            let mut bytes = [0u8; 8];
            getrandom::getrandom(&mut bytes).map_err(|error| {
                CoinageError::Internal(format!("drawing a jitter delay failed: {error}"))
            })?;
            let millis = u64::from_le_bytes(bytes) % (bound.as_millis() as u64).max(1);
            draws.push(core::time::Duration::from_millis(millis));
        }
        Ok(draws)
    }
}

/// Every record a sweep will touch, so it can hold them all before it starts.
fn sweep_locks(work: &[SweepWork]) -> LockSet {
    let mut locks = LockSet::default();
    for item in work {
        for (coin, _) in &item.aging_coins {
            locks.coins.push((item.purse, *coin));
        }
        for group in &item.rescues {
            for entry in &group.entries {
                locks.entries.push((item.purse, *entry));
            }
        }
    }
    locks
}

/// Purse lifecycle (§8.1).
///
/// Three of the five primitives touch no chain: a purse is a derivation namespace
/// plus a name, so creating, reading and renaming one are local facts. The other
/// two move value, and so are operations like any other.
impl CoinageLayer {
    /// Open a new purse (§8.1).
    ///
    /// The identifier is fresh and never reused, even after a purse is closed: it
    /// names a derivation namespace, so reissuing one would let a new purse's
    /// accounts be correlated with the closed purse's on-chain history.
    pub async fn create_purse<S: CoreStorage + ?Sized>(
        &mut self,
        storage: &S,
        name: String,
        now: Timestamp,
    ) -> Result<PurseId, CoinageError> {
        let purse = self.store_mut().create_purse(name);
        self.publish_and_persist(storage, now).await?;
        Ok(purse)
    }

    /// A purse's identity and balance, as of `now` (§8.1).
    pub fn query_purse(
        &self,
        purse: PurseId,
        now: Timestamp,
    ) -> Result<crate::host_logic::coinage::purse::PurseInfo, CoinageError> {
        self.store().purse_info(purse, now)
    }

    /// Rename a purse (§8.1).
    pub async fn rename_purse<S: CoreStorage + ?Sized>(
        &mut self,
        storage: &S,
        purse: PurseId,
        name: String,
        now: Timestamp,
    ) -> Result<(), CoinageError> {
        self.store_mut().rename_purse(purse, name)?;
        self.publish_and_persist(storage, now).await
    }

    /// Move `amount` from one purse to another (§8.1).
    ///
    /// Selection runs in the source purse; the destination coins are derived in the
    /// target purse's namespace, which is what keeps the two purses uncorrelated on
    /// chain. Change stays in the source.
    pub fn begin_rebalance(
        &mut self,
        from: PurseId,
        to: PurseId,
        amount: crate::host_logic::coinage::types::Amount,
        allow_degraded: bool,
        now: Timestamp,
    ) -> Result<OperationStart, CoinageError> {
        use crate::host_logic::coinage::selection::{OutputRequirement, SelectionRequest};
        use crate::host_logic::coinage::types::OperationKind;

        if self.store().purse(to).is_none() {
            return Err(CoinageError::PurseNotFound(to));
        }

        let request = SelectionRequest {
            amount,
            // The coins stay with the layer, so their shape is free.
            outputs: OutputRequirement::AnyDenominations,
            allow_degraded,
        };

        self.begin(
            from,
            OperationKind::Rebalance,
            &request,
            TargetDestinations::IntoPurse(to),
            now,
        )
    }

    /// Drain a purse into another and close it (§8.1).
    ///
    /// Refuses to strand value: a purse holding anything that cannot move right
    /// now — an entry still inside its jitter delay, a coin the chain has locked —
    /// is refused with `NoReadyEntries` rather than being closed around it. Closing
    /// a purse drops its records, and a record dropped while its account still
    /// holds a coin is value nobody can find again without a seed rescan.
    ///
    /// An empty purse needs no transaction and closes on the spot.
    pub fn begin_purse_deletion(
        &mut self,
        target: PurseId,
        drain_into: PurseId,
        allow_degraded: bool,
        now: Timestamp,
    ) -> Result<OperationStart, CoinageError> {
        use crate::host_logic::coinage::selection::{OutputRequirement, SelectionRequest};
        use crate::host_logic::coinage::types::{Amount, OperationKind};

        if target.is_main() {
            return Err(CoinageError::CannotDeleteMainPurse);
        }
        if self.store().purse(target).is_none() {
            return Err(CoinageError::PurseNotFound(target));
        }
        if self.store().purse(drain_into).is_none() {
            return Err(CoinageError::PurseNotFound(drain_into));
        }
        if self.store().has_in_flight_operations(target) {
            return Err(CoinageError::PurseHasInFlightOperations);
        }

        let balance = self.store().balance(target, now)?;
        let spendable = if allow_degraded {
            balance.spendable
        } else {
            balance.spendable_strict
        };
        if !balance.pending.is_zero() {
            return Err(CoinageError::NoReadyEntries {
                requested: spendable
                    .checked_add(balance.pending)
                    .unwrap_or(balance.pending),
                available_when_ready: spendable,
            });
        }

        let request = SelectionRequest {
            amount: spendable,
            outputs: OutputRequirement::AnyDenominations,
            allow_degraded,
        };
        let started = self.begin(
            target,
            OperationKind::DeletePurse,
            &request,
            TargetDestinations::IntoPurse(drain_into),
            now,
        )?;

        // The purse closes only once the chain has agreed its value left. Until
        // then the records have to stay: they are the only witness to coins whose
        // accounts are already on chain.
        self.register_completion(
            started.handle,
            Completion::ClosePurse {
                target,
                drained_into: drain_into,
                amount: if spendable.is_zero() {
                    Amount::ZERO
                } else {
                    spendable
                },
            },
        );
        Ok(started)
    }
}

/// What driving one transaction settled, if anything.
#[derive(Debug, Clone, PartialEq, Eq)]
enum Settlement {
    /// The chain finalized it successfully.
    Succeeded,
    /// It can never take effect. Its inputs are back in the pool.
    Rejected,
    /// Undecided. The entry stays pending and the operation stays open.
    Undecided,
}

impl CoinageLayer {
    /// Run every transaction of an operation's program, then terminate it.
    ///
    /// Returns once no transaction is left to submit and the operation has either
    /// terminated or been left for recovery. A failure here is a failure to
    /// *drive*; the operation's own outcome is reported through its status stream
    /// and its receipt, per §8.
    pub async fn drive_operation<S: CoreStorage + ?Sized>(
        &mut self,
        storage: &S,
        chain: &ChainContext<'_>,
        handle: OperationHandle,
        now: Timestamp,
    ) -> Result<(), CoinageError> {
        // An offload has no fixed program: it re-plans between phases, so it gets
        // its own loop rather than a list of transactions.
        if let Some(request) = self.take_offload(handle) {
            return self
                .drive_offload(storage, chain, handle, request, now)
                .await;
        }
        // A recovery scan has no transactions at all: it reads, it does not write.
        if let Some(request) = self.take_recovery(handle) {
            return self
                .drive_recovery(storage, chain, handle, request, now)
                .await;
        }

        let program = self
            .take_program(handle)
            .ok_or(CoinageError::OperationNotFound(handle))?;

        let mut grants = self
            .resolve_tokens(chain, program.unload_tokens_required(), now)
            .await?;

        // Coins already in the right shape are handed over with their secrets and
        // need nothing from the chain, so they can go out before anything is
        // submitted.
        self.deliver_exports(handle, &program.exports_in_place)?;

        let mut settlements = Vec::new();
        for transaction in &program.transactions {
            let settlement = self
                .run_transaction(storage, chain, handle, transaction, &mut grants, now)
                .await?;
            if settlement == Settlement::Succeeded {
                self.deliver_exports(handle, &transaction.exports)?;
            }
            settlements.push(settlement);
        }

        // Nothing else will be signed for this operation, so the secrets it was
        // handed have no further use (§8.5).
        self.forget_import_secrets(handle);
        self.terminate(storage, handle, &settlements, now).await
    }

    /// Assemble, log, broadcast and grade one transaction.
    async fn run_transaction<S: CoreStorage + ?Sized>(
        &mut self,
        storage: &S,
        chain: &ChainContext<'_>,
        handle: OperationHandle,
        transaction: &PlannedTransaction,
        grants: &mut Vec<TokenGrant>,
        now: Timestamp,
    ) -> Result<Settlement, CoinageError> {
        let (state, anchor) = submit::fetch_mortal_chain_state(chain.rpc)
            .await
            .map_err(|error| CoinageError::SubscriptionError(error.to_string()))?;
        let checkpoint = Checkpoint {
            number: anchor.number,
            hash: BlockHash(anchor.hash),
            mortality: anchor.period,
        };

        let assembled = self
            .assemble(chain, handle, transaction, &state, grants)
            .await?;
        let extrinsic_hash = submit::extrinsic_hash(&assembled.extrinsic);

        // The log entry and its hash are durable before anything is broadcast.
        let sequence = self.store_mut().plan_transaction(
            handle,
            transaction.inputs.clone(),
            transaction.outputs.clone(),
            checkpoint,
            transaction.depends_on.iter().copied(),
        )?;
        self.store_mut()
            .record_submission(handle, sequence, extrinsic_hash)?;
        if let Some(event) = assembled.event {
            self.store_mut().publish(event);
        }
        self.publish_and_persist(storage, now).await?;

        let outcome = submit::submit(chain.rpc, chain.metadata, &assembled.extrinsic).await;
        if let submit::TrackerOutcome::Included(verdict) = &outcome
            && verdict.succeeded()
        {
            self.deliver_memo(handle, transaction, &assembled.origins)?;
        }
        self.grade(storage, chain, handle, sequence, outcome, now)
            .await
    }

    /// Tell the caller which coins a transaction just sent outside the layer.
    ///
    /// Fired on inclusion rather than finality: §8.3 wants the payee to be able to
    /// act promptly, and accepts that a reorg can undo a delivered memo.
    fn deliver_memo(
        &self,
        handle: OperationHandle,
        transaction: &PlannedTransaction,
        origins: &[CoinAccountId],
    ) -> Result<(), CoinageError> {
        let Some(memo) = self.memo_of(handle) else {
            return Ok(());
        };

        let index = match transaction.kind {
            TransactionKind::Transfer { source, .. } | TransactionKind::Split { source, .. } => {
                source.1
            }
            // Neither an unload nor an import has a source coin of ours, so there
            // is no index to report.
            TransactionKind::Recycle { source, .. } => source.1,
            TransactionKind::TopUpLoad { .. } => crate::host_logic::coinage::types::CoinIndex(0),
            TransactionKind::Unload { .. }
            | TransactionKind::Offboard { .. }
            | TransactionKind::ImportTransfer { .. } => {
                crate::host_logic::coinage::types::CoinIndex(0)
            }
        };
        // One origin per output, in call order, so an unload's outputs are each
        // attributed to the entry alias they came from.
        let entries: Vec<MemoEntry> = transaction
            .kind
            .outputs()
            .iter()
            .zip(origins.iter().chain(core::iter::repeat(
                origins.last().unwrap_or(&CoinAccountId([0; 32])),
            )))
            .filter_map(|(output, origin)| match output.destination {
                Destination::External(recipient_account) => Some(MemoEntry {
                    sender_coin_account: *origin,
                    recipient_account,
                    derivation_index: index,
                }),
                Destination::Local { .. } => None,
            })
            .collect();

        if !entries.is_empty() {
            memo(entries);
        }
        Ok(())
    }

    /// Apply a tracker outcome, resolving the entry when the answer is definite
    /// and handing it to recovery when it is not.
    async fn grade<S: CoreStorage + ?Sized>(
        &mut self,
        storage: &S,
        chain: &ChainContext<'_>,
        handle: OperationHandle,
        sequence: u32,
        outcome: submit::TrackerOutcome,
        now: Timestamp,
    ) -> Result<Settlement, CoinageError> {
        match outcome {
            submit::TrackerOutcome::NotIncluded { reason } => {
                self.store_mut().resolve_transaction(
                    handle,
                    sequence,
                    LogEntryState::Rejected { reason },
                )?;
                self.publish_and_persist(storage, now).await?;
                Ok(Settlement::Rejected)
            }
            submit::TrackerOutcome::Included(verdict) if verdict.finalized() => {
                let state = if verdict.succeeded() {
                    LogEntryState::Succeeded {
                        block_hash: verdict.block_hash(),
                    }
                } else {
                    LogEntryState::Rejected {
                        reason: rejection_reason(&verdict),
                    }
                };
                let settled = if verdict.succeeded() {
                    Settlement::Succeeded
                } else {
                    Settlement::Rejected
                };
                self.store_mut()
                    .resolve_transaction(handle, sequence, state)?;
                self.publish_and_persist(storage, now).await?;
                Ok(settled)
            }
            // Seen in a block that is not finalized: real enough to report, not
            // real enough to retire a record over.
            submit::TrackerOutcome::Included(_) => {
                self.advance(storage, handle, OperationStatus::InBlock, now)
                    .await?;
                self.await_finality(storage, chain, handle, sequence, now)
                    .await
            }
            submit::TrackerOutcome::Unknown { .. } => {
                self.advance(storage, handle, OperationStatus::Recovering, now)
                    .await?;
                self.await_finality(storage, chain, handle, sequence, now)
                    .await
            }
        }
    }

    /// Run recovery passes until the entry is settled or the budget runs out.
    async fn await_finality<S: CoreStorage + ?Sized>(
        &mut self,
        storage: &S,
        chain: &ChainContext<'_>,
        handle: OperationHandle,
        sequence: u32,
        now: Timestamp,
    ) -> Result<Settlement, CoinageError> {
        for attempt in 0..RECOVERY_POLL_ATTEMPTS {
            if attempt > 0 {
                Delay::new(chain.recovery_poll_interval).await;
            }

            let at = recover::finalized_at(chain.rpc).await?;
            let entropy = self.entropy().to_vec();
            let outcome = recover::run_pass(chain.rpc, self.store_mut(), &entropy, &at).await?;
            self.publish_and_persist(storage, now).await?;

            if outcome.succeeded.contains(&(handle, sequence)) {
                return Ok(Settlement::Succeeded);
            }
            if outcome.rejected.contains(&(handle, sequence))
                || outcome.abandoned.contains(&(handle, sequence))
            {
                return Ok(Settlement::Rejected);
            }
        }

        // Not a verdict: the entry stays pending and recovery resumes it later.
        Ok(Settlement::Undecided)
    }

    /// Finish the operation from what its transactions settled.
    ///
    /// `Done` requires one definite success (§9). An operation with nothing
    /// settled either way is left open rather than failed: its transactions may
    /// still be on chain, and failing it would release records the chain is about
    /// to consume.
    async fn terminate<S: CoreStorage + ?Sized>(
        &mut self,
        storage: &S,
        handle: OperationHandle,
        settlements: &[Settlement],
        now: Timestamp,
    ) -> Result<(), CoinageError> {
        if settlements.contains(&Settlement::Undecided) {
            self.publish_and_persist(storage, now).await?;
            return Ok(());
        }
        // Nothing further can land, so none of the operation's side channels can
        // produce anything again.
        self.forget_memo(handle);
        self.close_exports(handle);
        self.forget_funding_origin(handle);

        let Some(operation) = self.store().operation(handle) else {
            // Already terminated, by recovery or a cascade.
            return Ok(());
        };
        let receipt = operation.log.receipt();
        let submitted_nothing = receipt.extrinsics.is_empty();

        if receipt.any_succeeded() || submitted_nothing {
            // An operation with nothing to submit — draining an empty purse —
            // succeeds by having nothing left to do.
            self.store_mut().conclude_operation(handle, receipt)?;
            self.apply_completion(handle)?;
        } else {
            let reason = first_rejection(&receipt)
                .unwrap_or_else(|| "no transaction reached the chain".to_string());
            self.store_mut().fail_operation(
                handle,
                CoinageError::ChainRejected {
                    extrinsic_hash: first_hash(&receipt).unwrap_or(ExtrinsicHash([0; 32])),
                    reason,
                },
            )?;
        }

        self.publish_and_persist(storage, now).await
    }

    /// Do the local work an operation's success unlocked.
    ///
    /// Runs after the operation record is gone, which is what lets a purse being
    /// drained pass the "no in-flight operations" check its own drain would
    /// otherwise fail.
    fn apply_completion(&mut self, handle: OperationHandle) -> Result<(), CoinageError> {
        match self.take_completion(handle) {
            Some(Completion::ClosePurse {
                target,
                drained_into,
                amount,
            }) => self.store_mut().close_purse(target, drained_into, amount),
            Some(Completion::ReportSweep {
                coins_recycled,
                entries_rescued,
            }) => {
                self.store_mut()
                    .publish(LayerEvent::MaintenanceSweepCompleted {
                        coins_recycled,
                        entries_rescued,
                        failed: 0,
                    });
                Ok(())
            }
            None => Ok(()),
        }
    }

    /// Move the operation to a non-terminal status and publish it.
    async fn advance<S: CoreStorage + ?Sized>(
        &mut self,
        storage: &S,
        handle: OperationHandle,
        status: OperationStatus,
        now: Timestamp,
    ) -> Result<(), CoinageError> {
        self.store_mut().advance_operation(handle, status)?;
        self.publish_and_persist(storage, now).await
    }

    /// Choose the tokens an operation's unloads will present.
    ///
    /// Resolved once for the whole operation: resolving per group would hand two
    /// groups the same free slot, and the second would be refused after the first
    /// had spent it.
    async fn resolve_tokens(
        &self,
        chain: &ChainContext<'_>,
        needed: usize,
        now: Timestamp,
    ) -> Result<Vec<TokenGrant>, CoinageError> {
        if needed == 0 {
            return Ok(Vec::new());
        }

        let at = chain
            .rpc
            .finalized_head()
            .await
            .map_err(|error| CoinageError::SubscriptionError(error.to_string()))?;
        let personhood = bandersnatch_entropy(self.entropy());
        let free = tokens::read_free_token_availability(
            chain.rpc,
            personhood,
            now,
            self.params(),
            self.constants(),
            &at,
        )
        .await?;
        let paid = tokens::read_paid_ring_state(
            chain.rpc,
            chain.metadata,
            self.entropy(),
            now,
            self.params(),
            self.constants(),
            &at,
        )
        .await?;
        // Whether a join is affordable is not readable: the pallet prices it from a
        // weight. A dry run is the only exact answer, and it costs one round trip
        // that is only spent when the free allowance is already exhausted.
        let paid = if paid.slots.iter().any(|slot| slot.is_joinable()) {
            let fundable = self.paid_join_is_fundable(chain, &paid).await?;
            paid.with_fundable_joins(fundable)
        } else {
            paid
        };

        let plan = resolve(needed, &free, &paid, self.params(), self.constants())?;

        // Every join must have *definitely* succeeded before the token it buys can
        // be presented, so they are submitted here, ahead of the operation's own
        // transactions, and awaited one at a time.
        for slot in &plan.joins {
            self.buy_paid_token(chain, paid.period, *slot).await?;
        }

        Ok(plan.grants)
    }

    /// Whether the fee account can pay to join the paid ring, as a dry run says.
    ///
    /// Dry-running the real extrinsic rather than comparing balances to a guess:
    /// the pallet computes the fee as `WeightToFee(coin_lifecycle_weight())`, which
    /// is neither a published constant nor a runtime API, so there is no number to
    /// compare against. A rejection is taken as "cannot fund" rather than raised,
    /// because the caller's alternative — reporting `NoUnloadToken` — is the same
    /// answer either way, and an unfunded fee account is an ordinary state.
    async fn paid_join_is_fundable(
        &self,
        chain: &ChainContext<'_>,
        paid: &PaidRingState,
    ) -> Result<bool, CoinageError> {
        let Some(slot) = paid.slots.iter().find(|slot| slot.is_joinable()) else {
            return Ok(false);
        };

        let extrinsic = self
            .assemble_paid_join(chain, paid.period, slot.slot)
            .await?;
        Ok(submit::dry_run(chain.rpc, &extrinsic).await.is_ok())
    }

    /// Build the extrinsic that registers one paid-token slot's key.
    async fn assemble_paid_join(
        &self,
        chain: &ChainContext<'_>,
        period: u32,
        slot: u32,
    ) -> Result<Vec<u8>, CoinageError> {
        let (state, _anchor) = submit::fetch_mortal_chain_state(chain.rpc)
            .await
            .map_err(|error| CoinageError::SubscriptionError(error.to_string()))?;
        let keypair = derivation::fee_account_keypair(self.entropy())?;
        let nonce = read_account_nonce(chain.rpc, self.fee_account()).await?;

        let member_key = derivation::paid_token_member_key(self.entropy(), period, slot)?;
        // The proof binds the key to whoever is joining, which is the fee account:
        // the pallet checks this signature in the call itself, against the origin.
        let ownership =
            proof::paid_token_ownership_proof(self.entropy(), period, slot, self.fee_account())?;
        let args = PayForUnloadFeeTokenArgs::new(member_key, ownership);
        let call = build_call(
            chain.metadata,
            CoinageCall::PayForRecyclerUnloadFeeTokenWithNative,
            &args,
        )?;

        build_account_signed_extrinsic(chain.metadata, &state, &call, &keypair, nonce)
    }

    /// Buy one paid unload token, and refuse to proceed until it is provable.
    ///
    /// # Why this is not a transaction in the operation's program
    ///
    /// Every other submission this layer makes gets a write-ahead log entry,
    /// because it moves records whose local state has to be reconciled if the
    /// process dies mid-flight. A join moves no records: it publishes a key derived
    /// deterministically from the wallet's entropy, and the chain's own
    /// `PaidUnloadTokenMembers` is the durable record of it. After a crash,
    /// `read_paid_ring_state` observes exactly what happened with no local
    /// bookkeeping, so a log entry would describe state the log does not own.
    ///
    /// # Why a bought token may still not be usable
    ///
    /// Registration and onboarding are separate steps: the pallet records the
    /// member at once, and the members pallet places it in a provable ring
    /// afterwards. A ring-VRF proof needs the ring, so a slot in between is paid for
    /// and unusable. The layer cannot wait — it has no clock and no sleep of its own
    /// (truapi#356) — so it reports the state honestly and the caller retries. The
    /// fee is spent either way, and retrying costs nothing further: the slot is
    /// already registered, so resolution will find it rather than buy a second one.
    async fn buy_paid_token(
        &self,
        chain: &ChainContext<'_>,
        period: u32,
        slot: u32,
    ) -> Result<(), CoinageError> {
        let extrinsic = self.assemble_paid_join(chain, period, slot).await?;
        // Definite success only. An optimistic inclusion is not enough: a reorg
        // that removed the join would leave the layer proving membership of a ring
        // its key is not in, which reads as an invalid proof with nothing to say
        // why.
        match submit::submit(chain.rpc, chain.metadata, &extrinsic).await {
            submit::TrackerOutcome::Included(submit::SubmissionVerdict::Succeeded {
                finalized: true,
                ..
            }) => {}
            submit::TrackerOutcome::Included(submit::SubmissionVerdict::DispatchFailed {
                reason,
                ..
            }) => {
                return Err(CoinageError::Internal(format!(
                    "buying a paid unload token for period {period} slot {slot} was refused: \
                     {reason}"
                )));
            }
            // Included but not yet final, or unknown, or provably not included.
            // None of these is a token the layer may present, and the fee account's
            // own state is what a retry will read, so nothing is recorded here.
            _ => return Err(CoinageError::NoUnloadToken),
        }

        // Re-read rather than assume: the pallet chose the period from its own
        // clock at dispatch, and the members pallet chose the ring.
        let at = chain
            .rpc
            .finalized_head()
            .await
            .map_err(|error| CoinageError::SubscriptionError(error.to_string()))?;
        let collection = storage::paid_token_collection_id(period);
        let member_key = derivation::paid_token_member_key(self.entropy(), period, slot)?;
        if ring::find_ring_including(chain.rpc, chain.metadata, &collection, &member_key, &at)
            .await?
            .is_none()
        {
            return Err(CoinageError::NoUnloadToken);
        }

        Ok(())
    }

    /// Assemble the extrinsic for one planned transaction.
    async fn assemble(
        &self,
        chain: &ChainContext<'_>,
        handle: OperationHandle,
        transaction: &PlannedTransaction,
        state: &ChainState,
        grants: &mut Vec<TokenGrant>,
    ) -> Result<Assembled, CoinageError> {
        match &transaction.kind {
            TransactionKind::Transfer { source, to } => {
                let args = TransferArgs::new(self.account_of(to)?);
                let call = build_call(chain.metadata, CoinageCall::Transfer, &args)?;
                Ok(Assembled {
                    extrinsic: self.sign_as_coin(chain.metadata, state, &call, *source)?,
                    event: None,
                    origins: vec![self.coin_account(*source)?],
                })
            }
            TransactionKind::ImportTransfer { secret, from, to } => {
                let keypair = self
                    .import_secret(handle, *secret)
                    .ok_or(CoinageError::BadCoinSecret)
                    .and_then(keypair_from)?;
                // The account the secret controls must be the one the coin sits
                // in, or the extrinsic would move a different coin — or none.
                if keypair.public.to_bytes() != from.0 {
                    return Err(CoinageError::BadCoinSecret);
                }

                let args = TransferArgs::new(self.account_of(to)?);
                let call = build_call(chain.metadata, CoinageCall::Transfer, &args)?;
                Ok(Assembled {
                    extrinsic: build_coin_origin_extrinsic(chain.metadata, state, &call, &keypair)?,
                    event: None,
                    origins: vec![*from],
                })
            }
            TransactionKind::TopUpLoad { purse, entries } => {
                let origin = self.funding_origin(handle).ok_or_else(|| {
                    CoinageError::Internal(
                        "a top-up needs the funding origin that signs for it".to_string(),
                    )
                })?;
                self.assemble_top_up(chain, state, *purse, entries, origin.as_ref())
                    .await
            }
            TransactionKind::Recycle { source, entry } => {
                let member_key = derivation::entry_member_key(self.entropy(), entry.0, entry.1)?;
                let coin_account = self.coin_account(*source)?;
                let ownership =
                    proof::entry_ownership_proof(self.entropy(), entry.0, entry.1, coin_account)?;
                let args = LoadRecyclerWithCoinArgs::new(member_key, ownership);
                let call = build_call(chain.metadata, CoinageCall::LoadRecyclerWithCoin, &args)?;

                Ok(Assembled {
                    extrinsic: self.sign_as_coin(chain.metadata, state, &call, *source)?,
                    event: None,
                    origins: vec![coin_account],
                })
            }
            TransactionKind::Split {
                source,
                source_exponent,
                outputs,
            } => {
                let args = SplitArgs::new(
                    *source_exponent,
                    &self.coin_outputs(outputs)?,
                    self.constants(),
                )?;
                let call = build_call(chain.metadata, CoinageCall::Split, &args)?;
                Ok(Assembled {
                    extrinsic: self.sign_as_coin(chain.metadata, state, &call, *source)?,
                    event: None,
                    origins: vec![self.coin_account(*source)?],
                })
            }
            TransactionKind::Offboard {
                purse,
                ring,
                exponent,
                entries,
                destination,
                payout,
                vouchers,
            } => {
                let grant = if grants.is_empty() {
                    None
                } else {
                    Some(grants.remove(0))
                };
                self.assemble_offboard(
                    chain,
                    state,
                    *purse,
                    *ring,
                    *exponent,
                    entries,
                    *destination,
                    *payout,
                    vouchers,
                    grant,
                )
                .await
            }
            TransactionKind::Unload {
                purse,
                ring,
                exponent,
                entries,
                outputs,
            } => {
                let grant = if grants.is_empty() {
                    None
                } else {
                    Some(grants.remove(0))
                };
                self.assemble_unload(
                    chain, state, *purse, *ring, *exponent, entries, outputs, grant,
                )
                .await
            }
        }
    }

    /// Read the ring an entry sits in, at the revision its members belong to now.
    ///
    /// The revision comes from the chain rather than from the local record: a proof
    /// is only valid against the revision it was built for, and a record observed an
    /// hour ago may name one the chain has since moved past.
    async fn read_ring_for(
        &self,
        chain: &ChainContext<'_>,
        exponent: DenominationExponent,
        ring_at: RingLocation,
        at: &str,
    ) -> Result<ring::RecyclerRing, CoinageError> {
        let revision =
            ring::read_ring_revision(chain.rpc, chain.metadata, exponent, ring_at.index, at)
                .await?
                .ok_or_else(|| {
                    CoinageError::Internal(format!(
                        "ring {:?} has no root on chain, so nothing can be proven against it",
                        ring_at.index
                    ))
                })?;

        ring::read_recycler_ring(
            chain.rpc,
            chain.metadata,
            exponent,
            RingLocation::new(ring_at.index, revision),
            at,
        )
        .await
    }

    /// Prove membership for every entry in a group, in the order the call names
    /// them.
    ///
    /// The aliases were derived without proving so the call could be built first;
    /// proving now must reproduce them, or the call names one entry and the proof
    /// authorizes another.
    fn prove_aliases(
        &self,
        ring: &ring::RecyclerRing,
        purse: PurseId,
        entries: &[crate::host_logic::coinage::types::EntryIndex],
        aliases: &[[u8; 32]],
        implication: &[u8],
    ) -> Result<Vec<RawEncoded>, CoinageError> {
        let mut proofs = Vec::with_capacity(entries.len());
        for (index, expected) in entries.iter().zip(aliases) {
            let proven = proof::entry_membership_proof(
                ring.domain,
                self.entropy(),
                purse,
                *index,
                &ring.members,
                implication,
            )?;
            if &proven.alias != expected {
                return Err(CoinageError::Internal(format!(
                    "entry {index:?} proved alias does not match the one the call names"
                )));
            }
            proofs.push(proven.proof);
        }
        Ok(proofs)
    }

    /// The extension that presents an unload token for a set of alias proofs.
    async fn token_origin(
        &self,
        chain: &ChainContext<'_>,
        grant: Option<TokenGrant>,
        alias_proofs: Vec<RawEncoded>,
        implication: &[u8],
    ) -> Result<AsCoinageInfo, CoinageError> {
        match grant {
            Some(TokenGrant::Free { period, counter }) => {
                let personhood = bandersnatch_entropy(self.entropy());
                // Scanning back from the current ring index is how every other
                // caller locates its membership: a key onboarded a while ago sits in
                // an older ring, and only the newest ring containing it is provable.
                let newest =
                    crate::runtime::statement_allowance::ring::read_current_ring_index(chain.rpc)
                        .await
                        .map_err(|error| {
                            CoinageError::Internal(format!("reading the ring index: {error}"))
                        })?;
                let people = crate::runtime::statement_allowance::find_including_ring(
                    chain.rpc,
                    chain.metadata,
                    personhood,
                    newest,
                )
                .await
                .map_err(|error| {
                    CoinageError::Internal(format!("locating the personhood ring: {error}"))
                })?
                .ok_or(CoinageError::NoUnloadToken)?;
                let domain = crate::runtime::statement_allowance::proof::domain_for_ring_exponent(
                    people.exponent,
                )
                .map_err(|error| {
                    CoinageError::Internal(format!("personhood ring domain: {error}"))
                })?;
                let token = proof::free_token_proof(
                    domain,
                    personhood,
                    &people.members,
                    period,
                    counter,
                    &alias_proofs,
                    implication,
                )?;

                Ok(AsCoinageInfo::FreeUnloadToken {
                    ring: FreeTokenRing::LitePeople,
                    proof: token,
                    period,
                    counter,
                    alias_proofs,
                })
            }
            Some(TokenGrant::Paid { period, slot }) => {
                let at = chain
                    .rpc
                    .finalized_head()
                    .await
                    .map_err(|error| CoinageError::SubscriptionError(error.to_string()))?;
                let collection = storage::paid_token_collection_id(period);
                let member_key = derivation::paid_token_member_key(self.entropy(), period, slot)?;

                // The ring the chain put this key in, not the one the join asked
                // for: `add_member` picks the period from its own clock and the
                // members pallet picks the ring.
                let ring = ring::find_ring_including(
                    chain.rpc,
                    chain.metadata,
                    &collection,
                    &member_key,
                    &at,
                )
                .await?
                .ok_or(CoinageError::NoUnloadToken)?;

                let token = proof::paid_token_proof(
                    ring.domain,
                    self.entropy(),
                    &ring.members,
                    period,
                    slot,
                    &alias_proofs,
                    implication,
                )?;

                Ok(AsCoinageInfo::PaidUnloadToken {
                    proof: token,
                    period,
                    ring: ring.location,
                    alias_proofs,
                })
            }
            None => Err(CoinageError::NoUnloadToken),
        }
    }

    /// Assemble one unload group, choosing its fee mode and origin.
    #[allow(clippy::too_many_arguments)]
    async fn assemble_unload(
        &self,
        chain: &ChainContext<'_>,
        state: &ChainState,
        purse: PurseId,
        ring_at: RingLocation,
        exponent: DenominationExponent,
        entries: &[crate::host_logic::coinage::types::EntryIndex],
        outputs: &[PlannedOutput],
        grant: Option<TokenGrant>,
    ) -> Result<Assembled, CoinageError> {
        let at = chain
            .rpc
            .finalized_head()
            .await
            .map_err(|error| CoinageError::SubscriptionError(error.to_string()))?;

        let ring = self.read_ring_for(chain, exponent, ring_at, &at).await?;

        let coin_outputs = self.coin_outputs(outputs)?;
        let aliases = entries
            .iter()
            .map(|index| proof::recycler_alias(self.entropy(), purse, *index))
            .collect::<Result<Vec<_>, _>>()?;

        // Price the prepaid shape, then let the fee account's balance decide.
        let prepaid = self
            .build_unload(
                chain,
                state,
                purse,
                &ring,
                exponent,
                entries,
                &aliases,
                &coin_outputs,
                Origin::Token(grant),
                0,
            )
            .await?;
        let estimated = fee::estimate(chain.rpc, &prepaid).await?;
        let balance =
            tokens::read_fee_account_balance(chain.rpc, chain.metadata, self.fee_account(), &at)
                .await?;
        let mode = choose_fee_mode(balance, estimated);

        let (extrinsic, paid) = match mode {
            FeeMode::Prepaid => (prepaid, grant.is_some_and(|grant| grant.is_paid())),
            FeeMode::FromOutput => {
                // No token is consumed in this mode, so the free allowance is
                // left alone and the ceiling is priced against its own bytes.
                let ceiling = fee::ceiling(chain.rpc, |max_fee| {
                    self.build_unload(
                        chain,
                        state,
                        purse,
                        &ring,
                        exponent,
                        entries,
                        &aliases,
                        &coin_outputs,
                        Origin::FromOutput,
                        max_fee,
                    )
                })
                .await?;
                (ceiling, false)
            }
        };

        Ok(Assembled {
            extrinsic,
            event: Some(LayerEvent::UnloadTokenSpent {
                purse,
                paid,
                fee: mode,
            }),
            origins: aliases.iter().copied().map(CoinAccountId).collect(),
        })
    }

    /// Assemble one offboard group: value out, surplus reloaded (§8.6).
    ///
    /// Structurally an unload, so it shares the ring read, the alias proofs and the
    /// token — but its outputs are an external payment plus fresh entries rather
    /// than coins, and there is no from-output fee mode to fall back on: the call
    /// carries no fee ceiling, so an unfunded fee account is a refusal rather than
    /// a cheaper path.
    #[allow(clippy::too_many_arguments)]
    async fn assemble_offboard(
        &self,
        chain: &ChainContext<'_>,
        state: &ChainState,
        purse: PurseId,
        ring_at: RingLocation,
        exponent: DenominationExponent,
        entries: &[crate::host_logic::coinage::types::EntryIndex],
        destination: CoinAccountId,
        payout: crate::host_logic::coinage::types::Amount,
        vouchers: &[(
            DenominationExponent,
            crate::host_logic::coinage::types::EntryIndex,
        )],
        grant: Option<TokenGrant>,
    ) -> Result<Assembled, CoinageError> {
        use crate::runtime::coinage::call::UnloadRecyclerIntoExternalAssetAndVouchersArgs;

        let at = chain
            .rpc
            .finalized_head()
            .await
            .map_err(|error| CoinageError::SubscriptionError(error.to_string()))?;
        let ring = self.read_ring_for(chain, exponent, ring_at, &at).await?;

        let aliases = entries
            .iter()
            .map(|index| proof::recycler_alias(self.entropy(), purse, *index))
            .collect::<Result<Vec<_>, _>>()?;
        let voucher_keys = vouchers
            .iter()
            .map(|(exponent, index)| {
                derivation::entry_member_key(self.entropy(), purse, *index)
                    .map(|member_key| (*exponent, member_key))
            })
            .collect::<Result<Vec<_>, _>>()?;

        let args = UnloadRecyclerIntoExternalAssetAndVouchersArgs::new(
            aliases.clone(),
            exponent,
            ring.location,
            destination,
            payout,
            &voucher_keys,
            self.constants(),
        )?;
        let call = build_call(
            chain.metadata,
            CoinageCall::UnloadRecyclerIntoExternalAssetAndVouchers,
            &args,
        )?;
        let implication = inherited_implication(chain.metadata, &call, state)?;
        let alias_proofs = self.prove_aliases(&ring, purse, entries, &aliases, &implication)?;
        let info = self
            .token_origin(chain, grant, alias_proofs, &implication)
            .await?;
        let extra = info.encode_extra(chain.metadata)?;

        Ok(Assembled {
            extrinsic: build_unsigned_extrinsic(chain.metadata, state, &call, &extra)?,
            event: Some(LayerEvent::UnloadTokenSpent {
                purse,
                paid: grant.is_some_and(|grant| grant.is_paid()),
                fee: FeeMode::Prepaid,
            }),
            origins: aliases.iter().copied().map(CoinAccountId).collect(),
        })
    }

    /// Build one unload extrinsic for a given origin and fee ceiling.
    #[allow(clippy::too_many_arguments)]
    async fn build_unload(
        &self,
        chain: &ChainContext<'_>,
        state: &ChainState,
        purse: PurseId,
        ring: &ring::RecyclerRing,
        exponent: DenominationExponent,
        entries: &[crate::host_logic::coinage::types::EntryIndex],
        aliases: &[[u8; 32]],
        outputs: &[CoinOutput],
        origin: Origin,
        max_fee: u128,
    ) -> Result<Vec<u8>, CoinageError> {
        let args = UnloadRecyclerIntoCoinsArgs::new(
            aliases.to_vec(),
            exponent,
            ring.location,
            outputs,
            max_fee,
            self.constants(),
        )?;
        let call = build_call(chain.metadata, CoinageCall::UnloadRecyclerIntoCoins, &args)?;
        let implication = inherited_implication(chain.metadata, &call, state)?;
        let alias_proofs = self.prove_aliases(ring, purse, entries, aliases, &implication)?;

        let info = match origin {
            Origin::Token(grant) => {
                self.token_origin(chain, grant, alias_proofs, &implication)
                    .await?
            }
            Origin::FromOutput => AsCoinageInfo::UnloadTokenFromOutput {
                fee_recycler_value: exponent,
                fee_recycler_ring: ring.location,
                retry_counter: 0,
                alias_proofs,
            },
        };

        let extra = info.encode_extra(chain.metadata)?;
        build_unsigned_extrinsic(chain.metadata, state, &call, &extra)
    }

    /// Sign a call with the coin that authorizes it.
    fn sign_as_coin(
        &self,
        metadata: &Metadata,
        state: &ChainState,
        call: &[u8],
        source: (PurseId, crate::host_logic::coinage::types::CoinIndex),
    ) -> Result<Vec<u8>, CoinageError> {
        let keypair = derivation::coin_keypair(self.entropy(), source.0, source.1)?;
        build_coin_origin_extrinsic(metadata, state, call, &keypair)
    }

    /// The on-chain account of one of our coins.
    fn coin_account(
        &self,
        source: (PurseId, crate::host_logic::coinage::types::CoinIndex),
    ) -> Result<CoinAccountId, CoinageError> {
        derivation::coin_account_id(self.entropy(), source.0, source.1)
    }

    /// The account one planned output names.
    fn account_of(&self, output: &PlannedOutput) -> Result<CoinAccountId, CoinageError> {
        match output.destination {
            Destination::External(account) => Ok(account),
            Destination::Local { purse, index } => {
                derivation::coin_account_id(self.entropy(), purse, index)
            }
        }
    }

    /// Planned outputs as the call's `(denomination, account)` pairs.
    fn coin_outputs(&self, outputs: &[PlannedOutput]) -> Result<Vec<CoinOutput>, CoinageError> {
        outputs
            .iter()
            .map(|output| {
                Ok(CoinOutput {
                    exponent: output.exponent,
                    account: self.account_of(output)?,
                })
            })
            .collect()
    }
}

/// Which origin an unload presents.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Origin {
    /// An unload token, free or paid.
    Token(Option<TokenGrant>),
    /// No token: the fee comes out of the unloaded value.
    FromOutput,
}

/// An assembled extrinsic, plus anything worth telling subscribers about how it
/// was built.
struct Assembled {
    extrinsic: Vec<u8>,
    event: Option<LayerEvent>,
    /// On-chain origins the transaction spends, in call order: the coin account
    /// for a coin origin, one alias per entry for an unload. What a memo reports
    /// as the sender side.
    origins: Vec<CoinAccountId>,
}

/// The first rejection reason a receipt carries.
fn first_rejection(
    receipt: &crate::host_logic::coinage::operation::OperationReceipt,
) -> Option<String> {
    use crate::host_logic::coinage::operation::ExtrinsicOutcome;

    receipt
        .extrinsics
        .iter()
        .find_map(|record| match &record.outcome {
            ExtrinsicOutcome::Rejected { reason } | ExtrinsicOutcome::Abandoned { reason } => {
                Some(reason.clone())
            }
            ExtrinsicOutcome::Succeeded { .. } => None,
        })
}

/// The first extrinsic hash a receipt carries.
fn first_hash(
    receipt: &crate::host_logic::coinage::operation::OperationReceipt,
) -> Option<ExtrinsicHash> {
    receipt
        .extrinsics
        .iter()
        .find_map(|record| record.extrinsic_hash)
}

/// A dispatch failure's reason, for the log.
fn rejection_reason(verdict: &submit::SubmissionVerdict) -> String {
    match verdict {
        submit::SubmissionVerdict::DispatchFailed { reason, .. } => reason.clone(),
        submit::SubmissionVerdict::Succeeded { .. } => "succeeded".to_string(),
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;
    use std::sync::{Arc, Mutex as StdMutex};

    use futures::StreamExt;
    use parity_scale_codec::Encode;
    use truapi::v01;
    use truapi_platform::CoreStorageKey;

    use crate::host_logic::coinage::coin::CoinState;
    use crate::host_logic::coinage::entry::EntryLocalState;
    use crate::host_logic::coinage::memo::{MemoEntry, PaymentClassification};
    use crate::host_logic::coinage::params::CoinageParameters;
    use crate::host_logic::coinage::types::{
        Amount, CoinAge, CoinIndex, DenominationExponent, EntryIndex, RevisionIndex, RingIndex,
    };
    use crate::runtime::coinage::bootstrap::CoinageConfig;
    use crate::runtime::coinage::storage;
    use crate::runtime::coinage::testing::{
        FIXTURE, FakeChain, Inclusion, collection_info, ring_page, ring_status,
    };

    use super::*;

    const ENTROPY: [u8; 32] = [7; 32];
    const NOW: Timestamp = Timestamp(1_700_000_000_000);

    #[derive(Default)]
    struct MemStorage(StdMutex<HashMap<Vec<u8>, Vec<u8>>>);

    #[truapi_platform::async_trait]
    impl CoreStorage for MemStorage {
        async fn read_core_storage(
            &self,
            key: CoreStorageKey,
        ) -> Result<Option<Vec<u8>>, v01::GenericError> {
            Ok(self.0.lock().unwrap().get(&key.encode()).cloned())
        }
        async fn write_core_storage(
            &self,
            key: CoreStorageKey,
            value: Vec<u8>,
        ) -> Result<(), v01::GenericError> {
            self.0.lock().unwrap().insert(key.encode(), value);
            Ok(())
        }
        async fn clear_core_storage(&self, key: CoreStorageKey) -> Result<(), v01::GenericError> {
            self.0.lock().unwrap().remove(&key.encode());
            Ok(())
        }
    }

    fn block_on<F: core::future::Future>(future: F) -> F::Output {
        futures::executor::block_on(future)
    }

    fn metadata() -> Metadata {
        Metadata::decode(FIXTURE).expect("the fixture decodes")
    }

    fn exponent(value: i8) -> DenominationExponent {
        DenominationExponent::new(value).expect("exponent is in range")
    }

    /// A brought-up layer over an empty store.
    fn layer(storage: &MemStorage) -> CoinageLayer {
        block_on(CoinageLayer::initialize(
            storage,
            &metadata(),
            ENTROPY.to_vec(),
            &CoinageConfig::default(),
        ))
        .expect("initializes")
    }

    /// Give the purse a coin the chain already reports populated.
    fn fund(layer: &mut CoinageLayer, purse: PurseId, exponent_value: i8) -> CoinIndex {
        let index = layer
            .store_mut()
            .add_pending_coin(purse, exponent(exponent_value))
            .expect("purse exists");
        layer
            .store_mut()
            .observe_coin(purse, index, CoinAge(0))
            .expect("coin exists");
        index
    }

    fn recipient(exponent_value: i8, byte: u8) -> CoinOutput {
        CoinOutput {
            exponent: exponent(exponent_value),
            account: CoinAccountId([byte; 32]),
        }
    }

    /// A context whose recovery polling does not sleep, so a test that exercises
    /// the recovery path stays fast.
    fn context<'a>(rpc: &'a RpcClient, metadata: &'a Metadata) -> ChainContext<'a> {
        ChainContext {
            rpc,
            metadata,
            recovery_poll_interval: Duration::ZERO,
        }
    }

    /// Give the purse one ready entry, and tell the chain about the rings a proof
    /// for it needs: the recycler ring it sits in, and the personhood ring backing
    /// a free unload token.
    fn load_entry(layer: &mut CoinageLayer, chain: &FakeChain, ring: RingLocation) -> EntryIndex {
        let entry = layer
            .store_mut()
            .allocate_entry(PurseId::MAIN, exponent(4), NOW, Duration::ZERO)
            .expect("purse exists");
        layer
            .store_mut()
            .observe_entry_ring(
                PurseId::MAIN,
                entry,
                ring,
                64,
                &CoinageParameters::default(),
            )
            .expect("entry exists");
        prepare_ring_for(chain, entry, ring);
        entry
    }

    fn ring() -> RingLocation {
        RingLocation::new(RingIndex(3), RevisionIndex(0))
    }

    #[test]
    fn a_transfer_submits_one_extrinsic_per_coin_and_finishes_done() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let first = fund(&mut layer, PurseId::MAIN, 4);
        let second = fund(&mut layer, PurseId::MAIN, 4);
        let chain = FakeChain::default();
        let rpc = chain.rpc();
        let metadata = metadata();

        let started = layer
            .begin_transfer(
                PurseId::MAIN,
                Amount::from_cents(32),
                vec![recipient(4, 0xaa), recipient(4, 0xbb)],
                true,
                None,
                NOW,
            )
            .expect("32 cents are available");
        let handle = started.handle;

        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), handle, NOW))
            .expect("drives");

        assert_eq!(chain.submission_count(), 2, "one extrinsic per coin");
        for index in [first, second] {
            assert_eq!(
                layer
                    .store()
                    .coin(PurseId::MAIN, index)
                    .expect("record kept")
                    .state,
                CoinState::Spent
            );
        }
        assert!(layer.store().operation(handle).is_none());
        assert!(!layer.has_pending_program(handle));

        let items: Vec<OperationStatus> = block_on(started.status.collect());
        assert_eq!(items.first(), Some(&OperationStatus::Preparing));
        match items.last().expect("a terminal item") {
            OperationStatus::Done(receipt) => {
                assert_eq!(receipt.extrinsics.len(), 2);
                assert!(
                    receipt
                        .extrinsics
                        .iter()
                        .all(|record| record.outcome.succeeded())
                );
            }
            other => panic!("expected Done, got {other:?}"),
        }
    }

    #[test]
    fn the_settled_transaction_is_visible_in_the_durable_store() {
        // §7.4's ordering, checked where it can be observed: the persisted store
        // carries the outcome, so a restart resumes from it rather than from
        // nothing.
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        fund(&mut layer, PurseId::MAIN, 4);
        let chain = FakeChain::default();
        let rpc = chain.rpc();
        let metadata = metadata();

        let started = layer
            .begin_transfer(
                PurseId::MAIN,
                Amount::from_cents(16),
                vec![recipient(4, 0xaa)],
                true,
                None,
                NOW,
            )
            .expect("16 cents are available");

        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), started.handle, NOW))
            .expect("drives");

        let reloaded =
            block_on(crate::runtime::coinage::persistence::load(&storage, "Main")).expect("loads");
        assert_eq!(
            reloaded.coins_in(PurseId::MAIN)[0].state,
            CoinState::Spent,
            "the durable store reflects the settled transaction"
        );
        assert!(
            reloaded.open_operations().next().is_none(),
            "and the operation is closed there too"
        );
    }

    #[test]
    fn a_refused_broadcast_returns_the_coin_to_the_pool_and_fails_the_operation() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let coin = fund(&mut layer, PurseId::MAIN, 4);
        let chain = FakeChain::new(Inclusion::Rejected);
        let rpc = chain.rpc();
        let metadata = metadata();

        let started = layer
            .begin_transfer(
                PurseId::MAIN,
                Amount::from_cents(16),
                vec![recipient(4, 0xaa)],
                true,
                None,
                NOW,
            )
            .expect("16 cents are available");

        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), started.handle, NOW))
            .expect("drives");

        assert_eq!(
            chain.submission_count(),
            0,
            "a rejected dry-run never reaches the node"
        );
        assert_eq!(
            layer
                .store()
                .coin(PurseId::MAIN, coin)
                .expect("record exists")
                .state,
            CoinState::Available,
            "nothing happened on chain, so the coin is spendable again"
        );
        let items: Vec<OperationStatus> = block_on(started.status.collect());
        assert!(matches!(
            items.last(),
            Some(OperationStatus::Failed(CoinageError::ChainRejected { .. }))
        ));
    }

    #[test]
    fn a_failed_dispatch_keeps_the_coin_and_fails_the_operation() {
        // The coin is neither spent nor immediately reusable: the chain restored
        // it under a lock, and only observation may release it.
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let coin = fund(&mut layer, PurseId::MAIN, 4);
        let chain = FakeChain::new(Inclusion::FinalizedFailure);
        let rpc = chain.rpc();
        let metadata = metadata();

        let started = layer
            .begin_transfer(
                PurseId::MAIN,
                Amount::from_cents(16),
                vec![recipient(4, 0xaa)],
                true,
                None,
                NOW,
            )
            .expect("16 cents are available");

        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), started.handle, NOW))
            .expect("drives");

        assert_eq!(chain.submission_count(), 1, "it did reach the chain");
        assert_ne!(
            layer
                .store()
                .coin(PurseId::MAIN, coin)
                .expect("record exists")
                .state,
            CoinState::Spent,
            "a failed dispatch consumed nothing"
        );
        let items: Vec<OperationStatus> = block_on(started.status.collect());
        assert!(matches!(items.last(), Some(OperationStatus::Failed(_))));
    }

    #[test]
    fn an_optimistic_inclusion_waits_for_finalized_state_before_retiring_anything() {
        // The chain reports a non-finalized block. The transfer's output is a
        // recipient's account this layer cannot see, so recovery settles it by
        // asking whether the input coin is gone — which it is.
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let coin = fund(&mut layer, PurseId::MAIN, 4);
        let chain = FakeChain::new(Inclusion::InBlock);
        let rpc = chain.rpc();
        let metadata = metadata();

        let started = layer
            .begin_transfer(
                PurseId::MAIN,
                Amount::from_cents(16),
                vec![recipient(4, 0xaa)],
                true,
                None,
                NOW,
            )
            .expect("16 cents are available");

        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), started.handle, NOW))
            .expect("drives");

        assert_eq!(
            layer
                .store()
                .coin(PurseId::MAIN, coin)
                .expect("record exists")
                .state,
            CoinState::Spent,
            "settled only once finalized state agreed the input was consumed"
        );
        let items: Vec<OperationStatus> = block_on(started.status.collect());
        assert!(
            items.contains(&OperationStatus::InBlock),
            "the optimistic inclusion was reported: {items:?}"
        );
        assert!(matches!(items.last(), Some(OperationStatus::Done(_))));
    }

    #[test]
    fn an_unsatisfiable_transfer_fails_synchronously_and_locks_nothing() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        fund(&mut layer, PurseId::MAIN, 2);

        let refused = layer
            .begin_transfer(
                PurseId::MAIN,
                Amount::from_cents(16),
                vec![recipient(4, 0xaa)],
                true,
                None,
                NOW,
            )
            .expect_err("four cents cannot pay sixteen");

        assert!(matches!(refused, CoinageError::InsufficientFunds { .. }));
        assert!(
            !layer.store().has_in_flight_operations(PurseId::MAIN),
            "a refusal must not leave records locked"
        );
    }

    #[test]
    fn recipient_outputs_that_do_not_sum_to_the_amount_are_refused() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        fund(&mut layer, PurseId::MAIN, 4);

        let refused = layer
            .begin_transfer(
                PurseId::MAIN,
                Amount::from_cents(16),
                vec![recipient(3, 0xaa)],
                true,
                None,
                NOW,
            )
            .expect_err("eight cents is not sixteen");

        assert_eq!(refused, CoinageError::OutputsDoNotSumToAmount);
    }

    #[test]
    fn a_split_transfer_mints_the_recipients_coin_and_keeps_the_change() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        fund(&mut layer, PurseId::MAIN, 4);
        let chain = FakeChain::default();
        let rpc = chain.rpc();
        let metadata = metadata();

        let started = layer
            .begin_transfer(
                PurseId::MAIN,
                Amount::from_cents(8),
                vec![recipient(3, 0xcc)],
                true,
                None,
                NOW,
            )
            .expect("a 16-cent coin can pay 8");

        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), started.handle, NOW))
            .expect("drives");

        assert_eq!(
            chain.submission_count(),
            1,
            "one split, no follow-up transfer"
        );
        // The change record exists and is still pending: it becomes available
        // when observation confirms it, not when the split succeeds.
        let change: Vec<_> = layer
            .store()
            .coins_in(PurseId::MAIN)
            .into_iter()
            .filter(|coin| coin.exponent == exponent(3))
            .collect();
        assert_eq!(change.len(), 1);
        assert_eq!(change[0].state, CoinState::Pending);
        let items: Vec<OperationStatus> = block_on(started.status.collect());
        assert!(matches!(items.last(), Some(OperationStatus::Done(_))));
    }

    #[test]
    fn driving_an_operation_twice_submits_nothing_the_second_time() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        fund(&mut layer, PurseId::MAIN, 4);
        let chain = FakeChain::default();
        let rpc = chain.rpc();
        let metadata = metadata();
        let started = layer
            .begin_transfer(
                PurseId::MAIN,
                Amount::from_cents(16),
                vec![recipient(4, 0xaa)],
                true,
                None,
                NOW,
            )
            .expect("16 cents are available");

        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), started.handle, NOW))
            .expect("drives");
        let refused = block_on(layer.drive_operation(
            &storage,
            &context(&rpc, &metadata),
            started.handle,
            NOW,
        ))
        .expect_err("the program was taken, not borrowed");

        assert!(matches!(refused, CoinageError::OperationNotFound(_)));
        assert_eq!(chain.submission_count(), 1, "no double spend");
    }

    #[test]
    fn an_unload_transfer_spends_a_free_token_and_reports_its_cost() {
        // Tier three end to end: no coins, one ready entry, so the transfer is
        // carried by an unload that mints the recipient's coin directly.
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let chain = FakeChain::default();
        let rpc = chain.rpc();
        let metadata = metadata();
        let entry = load_entry(&mut layer, &chain, ring());
        // A funded fee account, so the prepaid origin is the one chosen.
        chain.set_storage(
            &storage::system_account_key(&layer.fee_account()),
            account_info(1_000_000),
        );

        let mut events = layer.subscribe_events();
        let started = layer
            .begin_transfer(
                PurseId::MAIN,
                Amount::from_cents(16),
                vec![recipient(4, 0xee)],
                true,
                None,
                NOW,
            )
            .expect("the entry is ready");

        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), started.handle, NOW))
            .expect("drives");

        assert_eq!(chain.submission_count(), 1, "one group, one extrinsic");
        assert_eq!(
            layer
                .store()
                .entry(PurseId::MAIN, entry)
                .expect("record kept")
                .local,
            EntryLocalState::Consumed
        );
        let published: Vec<LayerEvent> =
            core::iter::from_fn(|| futures::FutureExt::now_or_never(events.next()).flatten())
                .collect();
        assert!(
            published.iter().any(|event| matches!(
                event,
                LayerEvent::UnloadTokenSpent {
                    paid: false,
                    fee: FeeMode::Prepaid,
                    ..
                }
            )),
            "the token's class and the fee mode are reported: {published:?}"
        );
        let items: Vec<OperationStatus> = block_on(started.status.collect());
        assert!(matches!(items.last(), Some(OperationStatus::Done(_))));
    }

    #[test]
    fn an_unfunded_fee_account_takes_the_fee_from_the_output_and_spends_no_token() {
        // §6.6's fallback. The fee account holds nothing, so the unload presents
        // the from-output origin, which consumes no free slot at all.
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let chain = FakeChain::default();
        chain.set_fee(1_000);
        let rpc = chain.rpc();
        let metadata = metadata();
        load_entry(&mut layer, &chain, ring());

        let mut events = layer.subscribe_events();
        let started = layer
            .begin_transfer(
                PurseId::MAIN,
                Amount::from_cents(16),
                vec![recipient(4, 0xee)],
                true,
                None,
                NOW,
            )
            .expect("the entry is ready");

        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), started.handle, NOW))
            .expect("drives");

        let published: Vec<LayerEvent> =
            core::iter::from_fn(|| futures::FutureExt::now_or_never(events.next()).flatten())
                .collect();
        assert!(
            published.iter().any(|event| matches!(
                event,
                LayerEvent::UnloadTokenSpent {
                    paid: false,
                    fee: FeeMode::FromOutput,
                    ..
                }
            )),
            "an unfunded fee account takes the fee from the output: {published:?}"
        );
    }

    #[test]
    fn a_free_slot_the_chain_has_already_seen_is_not_spent_twice() {
        // The consumed-slot read is what stops a wallet from presenting a token
        // the runtime will refuse, after the proof has already been built.
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let chain = FakeChain::default();
        let rpc = chain.rpc();
        let metadata = metadata();
        load_entry(&mut layer, &chain, ring());
        chain.set_storage(
            &storage::system_account_key(&layer.fee_account()),
            account_info(1_000_000),
        );

        // Spend every slot the layer would probe.
        let personhood = crate::runtime::statement_allowance::bandersnatch_entropy(&ENTROPY);
        let periods = crate::runtime::coinage::tokens::eligible_periods(
            NOW,
            layer.constants().unload_token_period,
            layer.params().period_lookback_grace,
        )
        .expect("computes");
        let range = layer
            .params()
            .free_token_counter_search_range
            .min(layer.constants().max_free_unload_tokens_per_period);
        for period in periods {
            for counter in 0..range {
                let alias =
                    crate::runtime::coinage::tokens::free_token_alias(personhood, period, counter)
                        .expect("derives");
                chain.set_storage(
                    &storage::consumed_free_unload_tokens_key(period, &alias),
                    Vec::new(),
                );
            }
        }

        let started = layer
            .begin_transfer(
                PurseId::MAIN,
                Amount::from_cents(16),
                vec![recipient(4, 0xee)],
                true,
                None,
                NOW,
            )
            .expect("the entry is ready");
        let refused = block_on(layer.drive_operation(
            &storage,
            &context(&rpc, &metadata),
            started.handle,
            NOW,
        ))
        .expect_err("no free slot remains and the paid ring cannot be joined");

        assert_eq!(refused, CoinageError::NoUnloadToken);
        assert_eq!(chain.submission_count(), 0, "nothing was broadcast");
    }

    #[test]
    fn a_memo_names_the_coins_the_transfer_minted_for_the_payee() {
        // Delivered on inclusion, before finality, which is what lets a payee act
        // promptly — and what makes a reorg able to undo a payment it was already
        // told about.
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let source = fund(&mut layer, PurseId::MAIN, 4);
        let chain = FakeChain::default();
        let rpc = chain.rpc();
        let metadata = metadata();
        let delivered: Arc<StdMutex<Vec<Vec<MemoEntry>>>> = Arc::new(StdMutex::new(Vec::new()));
        let recorder = delivered.clone();

        let started = layer
            .begin_transfer(
                PurseId::MAIN,
                Amount::from_cents(8),
                vec![recipient(3, 0xcc)],
                true,
                Some(Box::new(move |entries| {
                    recorder.lock().unwrap().push(entries);
                })),
                NOW,
            )
            .expect("a 16-cent coin can pay 8");

        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), started.handle, NOW))
            .expect("drives");

        let batches = delivered.lock().unwrap().clone();
        assert_eq!(batches.len(), 1, "one call per transaction that landed");
        assert_eq!(
            batches[0],
            vec![MemoEntry {
                sender_coin_account: derivation::coin_account_id(&ENTROPY, PurseId::MAIN, source)
                    .expect("derives"),
                recipient_account: CoinAccountId([0xcc; 32]),
                derivation_index: source,
            }],
            "the change output stays out of the memo: it never left"
        );
    }

    #[test]
    fn a_transfer_that_never_reached_a_block_delivers_no_memo() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        fund(&mut layer, PurseId::MAIN, 4);
        let chain = FakeChain::new(Inclusion::Rejected);
        let rpc = chain.rpc();
        let metadata = metadata();
        let delivered: Arc<StdMutex<usize>> = Arc::new(StdMutex::new(0));
        let recorder = delivered.clone();

        let started = layer
            .begin_transfer(
                PurseId::MAIN,
                Amount::from_cents(16),
                vec![recipient(4, 0xaa)],
                true,
                Some(Box::new(move |_| {
                    *recorder.lock().unwrap() += 1;
                })),
                NOW,
            )
            .expect("16 cents are available");

        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), started.handle, NOW))
            .expect("drives");

        assert_eq!(
            *delivered.lock().unwrap(),
            0,
            "nothing was minted, so there is nothing to tell a payee about"
        );
    }

    #[test]
    fn an_unload_memo_attributes_each_coin_to_the_entry_it_came_from() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let chain = FakeChain::default();
        let rpc = chain.rpc();
        let metadata = metadata();
        let entry = load_entry(&mut layer, &chain, ring());
        chain.set_storage(
            &storage::system_account_key(&layer.fee_account()),
            account_info(1_000_000),
        );
        let delivered: Arc<StdMutex<Vec<Vec<MemoEntry>>>> = Arc::new(StdMutex::new(Vec::new()));
        let recorder = delivered.clone();

        let started = layer
            .begin_transfer(
                PurseId::MAIN,
                Amount::from_cents(16),
                vec![recipient(4, 0xee)],
                true,
                Some(Box::new(move |entries| {
                    recorder.lock().unwrap().push(entries);
                })),
                NOW,
            )
            .expect("the entry is ready");

        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), started.handle, NOW))
            .expect("drives");

        let batches = delivered.lock().unwrap().clone();
        assert_eq!(batches.len(), 1);
        assert_eq!(
            batches[0][0].sender_coin_account,
            CoinAccountId(
                crate::runtime::coinage::proof::recycler_alias(&ENTROPY, PurseId::MAIN, entry)
                    .expect("derives")
            ),
            "the origin of a minted coin is the alias the unload spent"
        );
        assert_eq!(batches[0][0].recipient_account, CoinAccountId([0xee; 32]));
    }

    // -- D1: purse lifecycle -------------------------------------------------

    #[test]
    fn a_purse_is_created_read_and_renamed_without_touching_the_chain() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);

        let savings =
            block_on(layer.create_purse(&storage, "Savings".to_string(), NOW)).expect("creates");
        let info = layer.query_purse(savings, NOW).expect("purse exists");
        assert_eq!(info.name, "Savings");
        assert_eq!(info.spendable, Amount::ZERO);

        block_on(layer.rename_purse(&storage, savings, "Rent".to_string(), NOW)).expect("renames");
        assert_eq!(
            layer.query_purse(savings, NOW).expect("exists").name,
            "Rent"
        );

        // Durable, and still nothing was submitted anywhere.
        let reloaded =
            block_on(crate::runtime::coinage::persistence::load(&storage, "Main")).expect("loads");
        assert_eq!(reloaded.purse(savings).expect("exists").name, "Rent");
    }

    #[test]
    fn a_rebalance_moves_value_into_the_target_purses_namespace() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let source_coin = fund(&mut layer, PurseId::MAIN, 4);
        let savings =
            block_on(layer.create_purse(&storage, "Savings".to_string(), NOW)).expect("creates");
        let chain = FakeChain::default();
        let rpc = chain.rpc();
        let metadata = metadata();

        let started = layer
            .begin_rebalance(PurseId::MAIN, savings, Amount::from_cents(16), true, NOW)
            .expect("16 cents are available");

        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), started.handle, NOW))
            .expect("drives");

        assert_eq!(chain.submission_count(), 1);
        assert_eq!(
            layer
                .store()
                .coin(PurseId::MAIN, source_coin)
                .expect("record kept")
                .state,
            CoinState::Spent
        );
        // The destination record lives in the target purse, pending until
        // observation confirms it.
        let received = layer.store().coins_in(savings);
        assert_eq!(received.len(), 1);
        assert_eq!(received[0].exponent, exponent(4));
        assert_eq!(received[0].state, CoinState::Pending);
        // And its account is derived in the target purse's namespace.
        assert_ne!(
            derivation::coin_account_id(&ENTROPY, savings, received[0].index).expect("derives"),
            derivation::coin_account_id(&ENTROPY, PurseId::MAIN, received[0].index)
                .expect("derives"),
        );
        let items: Vec<OperationStatus> = block_on(started.status.collect());
        assert!(matches!(items.last(), Some(OperationStatus::Done(_))));
    }

    #[test]
    fn a_rebalance_into_a_purse_that_does_not_exist_is_refused() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        fund(&mut layer, PurseId::MAIN, 4);

        let refused = layer
            .begin_rebalance(PurseId::MAIN, PurseId(9), Amount::from_cents(16), true, NOW)
            .expect_err("there is nowhere to put it");

        assert_eq!(refused, CoinageError::PurseNotFound(PurseId(9)));
        assert!(
            !layer.store().has_in_flight_operations(PurseId::MAIN),
            "and nothing was locked on the way to finding out"
        );
    }

    #[test]
    fn deleting_a_purse_drains_it_and_closes_it_only_once_the_value_has_moved() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let savings =
            block_on(layer.create_purse(&storage, "Savings".to_string(), NOW)).expect("creates");
        let coin = fund(&mut layer, savings, 4);
        let chain = FakeChain::default();
        let rpc = chain.rpc();
        let metadata = metadata();
        let mut events = layer.subscribe_events();

        let started = layer
            .begin_purse_deletion(savings, PurseId::MAIN, true, NOW)
            .expect("the purse is drainable");

        // Still open while the drain is in flight: the records are the only
        // witness to a coin whose account is already on chain.
        assert!(layer.store().purse(savings).is_some());

        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), started.handle, NOW))
            .expect("drives");

        assert_eq!(chain.submission_count(), 1);
        assert!(
            layer.store().purse(savings).is_none(),
            "closed once the chain agreed the value left"
        );
        assert_eq!(
            layer.store().coin(savings, coin),
            None,
            "and its records went with it"
        );
        assert_eq!(layer.store().coins_in(PurseId::MAIN).len(), 1);

        let published: Vec<LayerEvent> =
            core::iter::from_fn(|| futures::FutureExt::now_or_never(events.next()).flatten())
                .collect();
        assert!(
            published.iter().any(|event| matches!(
                event,
                LayerEvent::PurseDeleted {
                    drained_into: PurseId::MAIN,
                    ..
                }
            )),
            "subscribers are told where the value went: {published:?}"
        );
    }

    #[test]
    fn deleting_an_empty_purse_closes_it_without_a_transaction() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let savings =
            block_on(layer.create_purse(&storage, "Savings".to_string(), NOW)).expect("creates");
        let chain = FakeChain::default();
        let rpc = chain.rpc();
        let metadata = metadata();

        let started = layer
            .begin_purse_deletion(savings, PurseId::MAIN, true, NOW)
            .expect("an empty purse is drainable");
        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), started.handle, NOW))
            .expect("drives");

        assert_eq!(chain.submission_count(), 0, "there was nothing to move");
        assert!(layer.store().purse(savings).is_none());
        let items: Vec<OperationStatus> = block_on(started.status.collect());
        assert!(
            matches!(items.last(), Some(OperationStatus::Done(_))),
            "having nothing to do is success, not failure: {items:?}"
        );
    }

    #[test]
    fn a_purse_holding_value_that_cannot_move_yet_is_not_closed_around_it() {
        // The dangerous version of this: close the purse, drop the records, and
        // leave a coin on chain nobody can find without a seed rescan.
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let savings =
            block_on(layer.create_purse(&storage, "Savings".to_string(), NOW)).expect("creates");
        // A coin the chain has not confirmed yet: real value, not spendable.
        layer
            .store_mut()
            .add_pending_coin(savings, exponent(4))
            .expect("purse exists");

        let refused = layer
            .begin_purse_deletion(savings, PurseId::MAIN, true, NOW)
            .expect_err("the purse still holds value that cannot move");

        assert!(matches!(refused, CoinageError::NoReadyEntries { .. }));
        assert!(layer.store().purse(savings).is_some());
    }

    #[test]
    fn the_main_purse_cannot_be_deleted() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);

        assert_eq!(
            layer
                .begin_purse_deletion(PurseId::MAIN, PurseId::MAIN, true, NOW)
                .expect_err("the main purse exists by construction"),
            CoinageError::CannotDeleteMainPurse
        );
    }

    #[test]
    fn a_purse_with_an_operation_in_flight_cannot_be_deleted() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let savings =
            block_on(layer.create_purse(&storage, "Savings".to_string(), NOW)).expect("creates");
        fund(&mut layer, savings, 4);
        let _started = layer
            .begin_transfer(
                savings,
                Amount::from_cents(16),
                vec![recipient(4, 0xaa)],
                true,
                None,
                NOW,
            )
            .expect("16 cents are available");

        let refused = layer
            .begin_purse_deletion(savings, PurseId::MAIN, true, NOW)
            .expect_err("something else is already spending from it");

        assert_eq!(refused, CoinageError::PurseHasInFlightOperations);
    }

    #[test]
    fn a_drain_that_the_chain_refuses_leaves_the_purse_open() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let savings =
            block_on(layer.create_purse(&storage, "Savings".to_string(), NOW)).expect("creates");
        let coin = fund(&mut layer, savings, 4);
        let chain = FakeChain::new(Inclusion::Rejected);
        let rpc = chain.rpc();
        let metadata = metadata();

        let started = layer
            .begin_purse_deletion(savings, PurseId::MAIN, true, NOW)
            .expect("the purse is drainable");
        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), started.handle, NOW))
            .expect("drives");

        assert!(
            layer.store().purse(savings).is_some(),
            "the value never moved, so the purse still holds it"
        );
        assert_eq!(
            layer
                .store()
                .coin(savings, coin)
                .expect("record exists")
                .state,
            CoinState::Available,
            "and it is spendable again, so a later attempt can retry"
        );
    }

    // -- D3: export and import ----------------------------------------------

    #[test]
    fn exporting_a_coin_already_in_shape_hands_over_its_secret_with_no_extrinsic() {
        // The point of the seam: control of a coin moves with its secret, so an
        // export that needs no reshaping is free and instant.
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let coin = fund(&mut layer, PurseId::MAIN, 4);
        let chain = FakeChain::default();
        let rpc = chain.rpc();
        let metadata = metadata();

        let started = layer
            .begin_export(PurseId::MAIN, Amount::from_cents(16), true, NOW)
            .expect("16 cents are available");
        let handle = started.handle;

        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), handle, NOW))
            .expect("drives");

        assert_eq!(chain.submission_count(), 0, "nothing had to move on chain");
        let exported: Vec<ExportedCoin> = block_on(started.coins.collect());
        assert_eq!(exported.len(), 1);
        assert_eq!(exported[0].exponent, exponent(4));
        assert_eq!(
            exported[0].account,
            derivation::coin_account_id(&ENTROPY, PurseId::MAIN, coin).expect("derives")
        );
        // The secret really controls the account it is offered with.
        let keypair = derivation::coin_keypair(&ENTROPY, PurseId::MAIN, coin).expect("derives");
        assert_eq!(exported[0].secret, CoinSecret(keypair.secret.to_bytes()));

        // And the coin is gone from this layer's point of view, so selection will
        // not offer it again.
        assert_eq!(
            layer
                .store()
                .coin(PurseId::MAIN, coin)
                .expect("record kept")
                .state,
            CoinState::Spent
        );
        assert_eq!(
            layer
                .store()
                .balance(PurseId::MAIN, NOW)
                .expect("purse exists")
                .spendable,
            Amount::ZERO
        );
    }

    #[test]
    fn an_export_that_needs_reshaping_emits_only_after_definite_success() {
        // A secret handed out on optimistic inclusion would name a coin a reorg
        // could remove, so the split's output waits for finalized state.
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        fund(&mut layer, PurseId::MAIN, 4);
        let chain = FakeChain::default();
        let rpc = chain.rpc();
        let metadata = metadata();

        let started = layer
            .begin_export(PurseId::MAIN, Amount::from_cents(8), true, NOW)
            .expect("a 16-cent coin can export 8");

        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), started.handle, NOW))
            .expect("drives");

        assert_eq!(chain.submission_count(), 1, "one split");
        let exported: Vec<ExportedCoin> = block_on(started.coins.collect());
        assert_eq!(exported.len(), 1, "only the exported half leaves");
        assert_eq!(exported[0].exponent, exponent(3));
        // The change stayed, and is ours.
        let kept: Vec<_> = layer
            .store()
            .coins_in(PurseId::MAIN)
            .into_iter()
            .filter(|coin| coin.state != CoinState::Spent)
            .collect();
        assert_eq!(kept.len(), 1);
        assert_eq!(kept[0].exponent, exponent(3));
    }

    #[test]
    fn an_export_whose_transaction_is_refused_hands_out_nothing() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        fund(&mut layer, PurseId::MAIN, 4);
        let chain = FakeChain::new(Inclusion::Rejected);
        let rpc = chain.rpc();
        let metadata = metadata();

        let started = layer
            .begin_export(PurseId::MAIN, Amount::from_cents(8), true, NOW)
            .expect("a 16-cent coin can export 8");
        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), started.handle, NOW))
            .expect("drives");

        let exported: Vec<ExportedCoin> = block_on(started.coins.collect());
        assert!(
            exported.is_empty(),
            "the coin was never minted, so there is no secret to give"
        );
    }

    #[test]
    fn an_export_beyond_the_purses_means_is_refused_synchronously() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        fund(&mut layer, PurseId::MAIN, 2);

        let refused = layer
            .begin_export(PurseId::MAIN, Amount::from_cents(64), true, NOW)
            .expect_err("four cents cannot export sixty-four");

        assert!(matches!(refused, CoinageError::InsufficientFunds { .. }));
    }

    #[test]
    fn importing_a_coin_moves_it_into_our_namespace_under_a_fresh_index() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let chain = FakeChain::default();
        let rpc = chain.rpc();
        let metadata = metadata();

        // A coin held under a secret nobody in this layer derived.
        let (account, secret) = foreign_coin([0x33; 32]);
        chain.set_storage(
            &storage::coins_by_owner_key(&account),
            chain_coin(exponent(4), CoinAge(2)),
        );

        let started = block_on(layer.begin_import(
            &context(&rpc, &metadata),
            PurseId::MAIN,
            vec![(account, secret)],
        ))
        .expect("the chain holds the coin the secret controls");

        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), started.handle, NOW))
            .expect("drives");

        assert_eq!(chain.submission_count(), 1);
        let received = layer.store().coins_in(PurseId::MAIN);
        assert_eq!(received.len(), 1);
        assert_eq!(
            received[0].exponent,
            exponent(4),
            "the denomination came from the chain, not from the caller"
        );
        // The destination is ours, derived, and distinct from where the coin was.
        assert_ne!(
            derivation::coin_account_id(&ENTROPY, PurseId::MAIN, received[0].index)
                .expect("derives"),
            account
        );
        let items: Vec<OperationStatus> = block_on(started.status.collect());
        assert!(matches!(items.last(), Some(OperationStatus::Done(_))));
    }

    #[test]
    fn a_secret_that_does_not_control_its_account_is_refused() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let chain = FakeChain::default();
        let rpc = chain.rpc();
        let metadata = metadata();
        let (_, secret) = foreign_coin([0x44; 32]);

        let refused = block_on(layer.begin_import(
            &context(&rpc, &metadata),
            PurseId::MAIN,
            vec![(CoinAccountId([0xff; 32]), secret)],
        ))
        .expect_err("the secret controls a different account");

        assert_eq!(refused, CoinageError::BadCoinSecret);
        assert!(
            layer.store().coins_in(PurseId::MAIN).is_empty(),
            "and no record was allocated on the way to finding out"
        );
    }

    #[test]
    fn importing_a_coin_the_layer_already_holds_is_refused() {
        // Two records for one account would leave one of them a ghost: spending
        // through either would make the other unspendable without explanation.
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let chain = FakeChain::default();
        let rpc = chain.rpc();
        let metadata = metadata();
        let mine = fund(&mut layer, PurseId::MAIN, 4);
        let account = derivation::coin_account_id(&ENTROPY, PurseId::MAIN, mine).expect("derives");
        let keypair = derivation::coin_keypair(&ENTROPY, PurseId::MAIN, mine).expect("derives");

        let refused = block_on(layer.begin_import(
            &context(&rpc, &metadata),
            PurseId::MAIN,
            vec![(account, CoinSecret(keypair.secret.to_bytes()))],
        ))
        .expect_err("this coin is already ours");

        assert_eq!(refused, CoinageError::BadCoinSecret);
    }

    #[test]
    fn importing_a_coin_the_chain_does_not_hold_is_refused() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let chain = FakeChain::default();
        let rpc = chain.rpc();
        let metadata = metadata();
        let (account, secret) = foreign_coin([0x55; 32]);

        let refused = block_on(layer.begin_import(
            &context(&rpc, &metadata),
            PurseId::MAIN,
            vec![(account, secret)],
        ))
        .expect_err("there is no coin at that account");

        assert_eq!(refused, CoinageError::BadCoinSecret);
    }

    #[test]
    fn an_import_forgets_the_secrets_it_was_handed() {
        // §8.5. Holding them after submission keeps spendable material alive for
        // no purpose.
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let chain = FakeChain::default();
        let rpc = chain.rpc();
        let metadata = metadata();
        let (account, secret) = foreign_coin([0x66; 32]);
        chain.set_storage(
            &storage::coins_by_owner_key(&account),
            chain_coin(exponent(3), CoinAge(0)),
        );

        let started = block_on(layer.begin_import(
            &context(&rpc, &metadata),
            PurseId::MAIN,
            vec![(account, secret)],
        ))
        .expect("the chain holds the coin");
        assert!(layer.import_secret(started.handle, 0).is_some());

        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), started.handle, NOW))
            .expect("drives");

        assert!(
            layer.import_secret(started.handle, 0).is_none(),
            "the secrets are gone once nothing else will be signed with them"
        );
    }

    /// A coin held under a secret this layer never derived.
    fn foreign_coin(seed: [u8; 32]) -> (CoinAccountId, CoinSecret) {
        let mini = schnorrkel::MiniSecretKey::from_bytes(&seed).expect("32 bytes");
        let keypair = mini.expand_to_keypair(schnorrkel::ExpansionMode::Ed25519);
        (
            CoinAccountId(keypair.public.to_bytes()),
            CoinSecret(keypair.secret.to_bytes()),
        )
    }

    /// `Coinage::CoinsByOwner`'s value: the denomination and the age.
    fn chain_coin(exponent: DenominationExponent, age: CoinAge) -> Vec<u8> {
        storage::ChainCoin {
            value: exponent.get(),
            age: age.0,
        }
        .encode()
    }

    // -- the tick entry point ------------------------------------------------

    #[test]
    fn a_tick_recycles_an_aging_coin_without_the_caller_naming_a_sweep() {
        // The whole point of the entry point: a host that knows nothing about
        // sweeps, ages or rings gets the layer's autonomous behaviour by calling one
        // method on a timer.
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let old = fund_aged(&mut layer, PurseId::MAIN, 4, CoinAge(14));
        let chain = FakeChain::default();
        let rpc = chain.rpc();
        let metadata = metadata();

        let outcome = block_on(layer.tick(&storage, &context(&rpc, &metadata), NOW))
            .expect("the tick succeeds");

        assert!(outcome.swept, "an aging coin was due");
        assert_eq!(chain.submission_count(), 1);
        assert_eq!(
            layer
                .store()
                .coin(PurseId::MAIN, old)
                .expect("record kept")
                .state,
            CoinState::Spent
        );
    }

    #[test]
    fn a_tick_on_a_tidy_wallet_submits_nothing_and_still_advises_an_interval() {
        // A quiet tick must be cheap, because the host is expected to call it
        // regularly and most calls will find nothing to do.
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let chain = FakeChain::default();
        let rpc = chain.rpc();
        let metadata = metadata();

        let outcome = block_on(layer.tick(&storage, &context(&rpc, &metadata), NOW))
            .expect("the tick succeeds");

        assert!(!outcome.swept, "nothing was due");
        assert_eq!(chain.submission_count(), 0, "and nothing was submitted");
        assert_eq!(
            outcome.next_tick_after,
            CoinageParameters::default().sweep_tick_interval(),
            "a host still learns when to come back"
        );
    }

    #[test]
    fn ticking_repeatedly_is_harmless_because_scheduling_holds_no_state() {
        // Called far more often than the advised interval, the second tick must find
        // the work already done rather than redo it — which is what makes it safe
        // for a host to tick on any schedule, and safe across a restart.
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        fund_aged(&mut layer, PurseId::MAIN, 4, CoinAge(14));
        let chain = FakeChain::default();
        let rpc = chain.rpc();
        let metadata = metadata();
        let context = context(&rpc, &metadata);

        let first = block_on(layer.tick(&storage, &context, NOW)).expect("ticks");
        let second = block_on(layer.tick(&storage, &context, NOW)).expect("ticks again");

        assert!(first.swept);
        assert!(!second.swept, "the coin is already an entry");
        assert_eq!(
            chain.submission_count(),
            1,
            "the second tick spends no unload token and no fee"
        );
    }

    // -- D4: the two sweeps --------------------------------------------------

    #[test]
    fn an_aging_coin_is_recycled_into_an_entry() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let old = fund_aged(&mut layer, PurseId::MAIN, 4, CoinAge(14));
        let chain = FakeChain::default();
        let rpc = chain.rpc();
        let metadata = metadata();

        let started = layer
            .begin_maintenance_sweep(None, NOW)
            .expect("planning succeeds")
            .expect("there is work to do");

        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), started.handle, NOW))
            .expect("drives");

        assert_eq!(chain.submission_count(), 1, "one load per aging coin");
        assert_eq!(
            layer
                .store()
                .coin(PurseId::MAIN, old)
                .expect("record kept")
                .state,
            CoinState::Spent,
            "the coin became an entry"
        );
        let entries = layer.store().entries_in(PurseId::MAIN);
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].exponent, exponent(4));
        assert!(
            entries[0].ready_at > NOW,
            "a fresh entry waits out its jitter before it is selectable"
        );
    }

    #[test]
    fn a_young_coin_is_left_alone_and_the_sweep_reports_nothing_to_do() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        fund(&mut layer, PurseId::MAIN, 4);

        let nothing = layer
            .begin_maintenance_sweep(None, NOW)
            .expect("planning succeeds");

        assert!(
            nothing.is_none(),
            "a tidy wallet costs no operation and no event"
        );
    }

    #[test]
    fn an_entry_near_ring_expiry_is_rescued_back_into_a_coin() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let chain = FakeChain::default();
        let rpc = chain.rpc();
        let metadata = metadata();
        let entry = load_entry(&mut layer, &chain, ring());
        chain.set_storage(
            &storage::system_account_key(&layer.fee_account()),
            account_info(1_000_000),
        );
        // The ring became immutable long enough ago that the margin has been
        // crossed: the pallet destroys the backing value at expiry.
        let expiring = NOW.saturating_sub(
            layer.constants().recycler_expiration_time
                - layer
                    .params()
                    .rescue_margin(layer.constants().recycler_expiration_time),
        );
        layer
            .store_mut()
            .observe_entry_ring_immutability(PurseId::MAIN, entry, Some(expiring))
            .expect("entry exists");

        let started = layer
            .begin_maintenance_sweep(Some(vec![PurseId::MAIN]), NOW)
            .expect("planning succeeds")
            .expect("the entry is due");

        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), started.handle, NOW))
            .expect("drives");

        assert_eq!(chain.submission_count(), 1, "one unload per ring group");
        assert_eq!(
            layer
                .store()
                .entry(PurseId::MAIN, entry)
                .expect("record kept")
                .local,
            EntryLocalState::Consumed
        );
        // The value came back as a coin of the same denomination, in the same
        // purse.
        let coins = layer.store().coins_in(PurseId::MAIN);
        assert_eq!(coins.len(), 1);
        assert_eq!(coins[0].exponent, exponent(4));
    }

    #[test]
    fn an_entry_whose_ring_was_never_observed_is_not_rescued_and_that_is_not_reassurance() {
        // The hazard §4 of the status doc names. An entry with no observed
        // immutability has no deadline recorded, which is indistinguishable from a
        // ring still accepting members — so the sweep declines, and a caller must
        // not read that as "nothing is at risk".
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let chain = FakeChain::default();
        let entry = load_entry(&mut layer, &chain, ring());
        assert_eq!(
            layer
                .store()
                .entry(PurseId::MAIN, entry)
                .expect("exists")
                .ring_immutable_since,
            None,
            "the premise: nobody observed when this ring became immutable"
        );

        let nothing = layer
            .begin_maintenance_sweep(None, NOW)
            .expect("planning succeeds");

        assert!(
            nothing.is_none(),
            "silence here means 'no deadline known', not 'no deadline exists'"
        );
        // Ageing the clock past any plausible expiry changes nothing, because the
        // deadline is missing rather than distant.
        let much_later = NOW.saturating_add(core::time::Duration::from_secs(10_000 * 24 * 3_600));
        assert!(
            layer
                .begin_maintenance_sweep(None, much_later)
                .expect("planning succeeds")
                .is_none()
        );
    }

    #[test]
    fn a_sweep_reports_what_it_achieved() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        fund_aged(&mut layer, PurseId::MAIN, 4, CoinAge(14));
        fund_aged(&mut layer, PurseId::MAIN, 3, CoinAge(15));
        let chain = FakeChain::default();
        let rpc = chain.rpc();
        let metadata = metadata();
        let mut events = layer.subscribe_events();

        let started = layer
            .begin_maintenance_sweep(None, NOW)
            .expect("planning succeeds")
            .expect("two coins are due");
        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), started.handle, NOW))
            .expect("drives");

        let published: Vec<LayerEvent> =
            core::iter::from_fn(|| futures::FutureExt::now_or_never(events.next()).flatten())
                .collect();
        assert!(
            published
                .iter()
                .any(|event| matches!(event, LayerEvent::MaintenanceSweepStarted { .. })),
            "{published:?}"
        );
        assert!(
            published.iter().any(|event| matches!(
                event,
                LayerEvent::MaintenanceSweepCompleted {
                    coins_recycled: 2,
                    entries_rescued: 0,
                    ..
                }
            )),
            "{published:?}"
        );
    }

    #[test]
    fn a_sweep_holds_every_record_it_will_touch() {
        // Two overlapping sweeps would submit two recycles for one coin, and the
        // second would be refused after the first consumed it.
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        fund_aged(&mut layer, PurseId::MAIN, 4, CoinAge(14));

        let _first = layer
            .begin_maintenance_sweep(None, NOW)
            .expect("planning succeeds")
            .expect("a coin is due");
        let second = layer.begin_maintenance_sweep(None, NOW);

        // The coin is locked, so the second sweep finds nothing due rather than
        // planning the same work twice.
        assert!(matches!(second, Ok(None)), "unexpected: {second:?}");
    }

    #[test]
    fn a_sweep_of_a_purse_that_does_not_exist_is_refused() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);

        assert_eq!(
            layer
                .begin_maintenance_sweep(Some(vec![PurseId(7)]), NOW)
                .expect_err("there is no such purse"),
            CoinageError::PurseNotFound(PurseId(7))
        );
    }

    #[test]
    fn a_failed_recycle_leaves_the_coin_and_retires_the_entry_that_never_came() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let old = fund_aged(&mut layer, PurseId::MAIN, 4, CoinAge(14));
        let chain = FakeChain::new(Inclusion::Rejected);
        let rpc = chain.rpc();
        let metadata = metadata();

        let started = layer
            .begin_maintenance_sweep(None, NOW)
            .expect("planning succeeds")
            .expect("a coin is due");
        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), started.handle, NOW))
            .expect("drives");

        assert_eq!(
            layer
                .store()
                .coin(PurseId::MAIN, old)
                .expect("record exists")
                .state,
            CoinState::Available,
            "the coin is still spendable, and a later sweep can retry"
        );
        assert_eq!(
            layer.store().entries_in(PurseId::MAIN)[0].local,
            EntryLocalState::Consumed,
            "the entry that never came to exist is retired, index and all"
        );
    }

    /// A coin the chain reports at a given age.
    fn fund_aged(
        layer: &mut CoinageLayer,
        purse: PurseId,
        exponent_value: i8,
        age: CoinAge,
    ) -> CoinIndex {
        let index = layer
            .store_mut()
            .add_pending_coin(purse, exponent(exponent_value))
            .expect("purse exists");
        layer
            .store_mut()
            .observe_coin(purse, index, age)
            .expect("coin exists");
        index
    }

    // -- D5: external offload ------------------------------------------------

    #[test]
    fn an_offload_from_a_ready_entry_pays_out_and_finishes() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let chain = FakeChain::default();
        let rpc = chain.rpc();
        let metadata = metadata();
        let entry = load_entry(&mut layer, &chain, ring());
        chain.set_storage(
            &storage::system_account_key(&layer.fee_account()),
            account_info(1_000_000),
        );

        let started = layer
            .begin_external_offload(
                PurseId::MAIN,
                Amount::from_cents(16),
                CoinAccountId([0x77; 32]),
                true,
            )
            .expect("the purse exists");

        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), started.handle, NOW))
            .expect("drives");

        assert_eq!(chain.submission_count(), 1, "one group, one extrinsic");
        assert_eq!(
            layer
                .store()
                .entry(PurseId::MAIN, entry)
                .expect("record kept")
                .local,
            EntryLocalState::Consumed
        );
        let items: Vec<OperationStatus> = block_on(started.status.collect());
        assert!(matches!(items.last(), Some(OperationStatus::Done(_))));
    }

    #[test]
    fn an_offload_of_part_of_an_entry_reloads_the_surplus_as_entries() {
        // §8.6's invariant: surplus must never land as a coin, because that would
        // tie the entry-side anonymity set to a fresh account.
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let chain = FakeChain::default();
        let rpc = chain.rpc();
        let metadata = metadata();
        load_entry(&mut layer, &chain, ring());
        chain.set_storage(
            &storage::system_account_key(&layer.fee_account()),
            account_info(1_000_000),
        );

        let started = layer
            .begin_external_offload(
                PurseId::MAIN,
                Amount::from_cents(8),
                CoinAccountId([0x77; 32]),
                true,
            )
            .expect("the purse exists");
        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), started.handle, NOW))
            .expect("drives");

        // The 8-cent remainder came back as an entry, not as a coin.
        let entries = layer.store().entries_in(PurseId::MAIN);
        let surplus: Vec<_> = entries
            .iter()
            .filter(|entry| entry.exponent == exponent(3))
            .collect();
        assert_eq!(surplus.len(), 1, "the surplus is an entry: {entries:?}");
        assert!(
            layer.store().coins_in(PurseId::MAIN).is_empty(),
            "and no coin was minted on the way out"
        );
    }

    #[test]
    fn an_offload_recycles_a_coin_first_when_no_entry_is_ready() {
        // The loop's reason for existing: coins cannot be offboarded, so the
        // operation turns one into an entry and looks again.
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let chain = FakeChain::default();
        let rpc = chain.rpc();
        let metadata = metadata();
        let coin = fund(&mut layer, PurseId::MAIN, 4);
        chain.set_storage(
            &storage::system_account_key(&layer.fee_account()),
            account_info(1_000_000),
        );
        // No jitter, so the entry the recycle produces is usable in the next phase.
        layer.set_jitter_for_tests(core::time::Duration::ZERO);

        let started = layer
            .begin_external_offload(
                PurseId::MAIN,
                Amount::from_cents(16),
                CoinAccountId([0x77; 32]),
                true,
            )
            .expect("the purse exists");
        // The recycle's entry needs a ring on chain before it can be offboarded.
        let entry = EntryIndex(0);
        prepare_ring_for(&chain, entry, ring());

        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), started.handle, NOW))
            .expect("drives");

        assert_eq!(
            chain.submission_count(),
            2,
            "one recycle, then one offboard: {:?}",
            chain.calls().len()
        );
        assert_eq!(
            layer
                .store()
                .coin(PurseId::MAIN, coin)
                .expect("record kept")
                .state,
            CoinState::Spent,
            "the coin became the entry that was offboarded"
        );
        let items: Vec<OperationStatus> = block_on(started.status.collect());
        assert!(matches!(items.last(), Some(OperationStatus::Done(_))));
    }

    #[test]
    fn an_offload_beyond_the_purses_means_fails_on_the_status_stream() {
        // Not a synchronous error: the operation started, looked, and found the
        // purse could never cover it (§8.6 lists InsufficientFunds as terminal).
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let chain = FakeChain::default();
        let rpc = chain.rpc();
        let metadata = metadata();

        let started = layer
            .begin_external_offload(
                PurseId::MAIN,
                Amount::from_cents(16),
                CoinAccountId([0x77; 32]),
                true,
            )
            .expect("the purse exists");
        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), started.handle, NOW))
            .expect("drives");

        assert_eq!(chain.submission_count(), 0);
        let items: Vec<OperationStatus> = block_on(started.status.collect());
        assert!(
            matches!(
                items.last(),
                Some(OperationStatus::Failed(
                    CoinageError::InsufficientFunds { .. }
                ))
            ),
            "{items:?}"
        );
    }

    #[test]
    fn an_offload_waits_for_an_entry_that_is_still_ripening() {
        // The entry covers the amount but is inside its decorrelation delay, so the
        // operation reports Waiting rather than working around it.
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let chain = FakeChain::default();
        let rpc = chain.rpc();
        let metadata = metadata();
        let delay = core::time::Duration::from_secs(3_600);
        let entry = layer
            .store_mut()
            .allocate_entry(PurseId::MAIN, exponent(4), NOW, delay)
            .expect("purse exists");
        layer
            .store_mut()
            .observe_entry_ring(
                PurseId::MAIN,
                entry,
                ring(),
                64,
                &CoinageParameters::default(),
            )
            .expect("entry exists");
        prepare_ring_for(&chain, entry, ring());
        chain.set_storage(
            &storage::system_account_key(&layer.fee_account()),
            account_info(1_000_000),
        );

        let started = layer
            .begin_external_offload(
                PurseId::MAIN,
                Amount::from_cents(16),
                CoinAccountId([0x77; 32]),
                true,
            )
            .expect("the purse exists");
        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), started.handle, NOW))
            .expect("drives");

        let items: Vec<OperationStatus> = block_on(started.status.collect());
        assert!(
            items
                .iter()
                .any(|status| matches!(status, OperationStatus::Waiting(_))),
            "the wait is reported so a caller can show it: {items:?}"
        );
        // And once the delay has passed, the same operation offboards.
        assert!(
            chain.submission_count() >= 1,
            "the wait resolved into an offboard"
        );
    }

    #[test]
    fn an_offload_from_a_purse_that_does_not_exist_is_refused() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);

        assert_eq!(
            layer
                .begin_external_offload(
                    PurseId(9),
                    Amount::from_cents(16),
                    CoinAccountId([0x77; 32]),
                    true
                )
                .expect_err("there is no such purse"),
            CoinageError::PurseNotFound(PurseId(9))
        );
    }

    /// Tell the chain everything a read of one of our entries will ask for.
    fn prepare_ring_for(chain: &FakeChain, entry: EntryIndex, ring: RingLocation) {
        let member_key =
            derivation::entry_member_key(&ENTROPY, PurseId::MAIN, entry).expect("derives");
        let alias = crate::runtime::coinage::proof::recycler_alias(&ENTROPY, PurseId::MAIN, entry)
            .expect("derives");
        let mut members = vec![member_key];
        members.extend(fillers(15));

        chain.place_entry_in_ring(exponent(4), member_key, alias, ring, &members, None);
        set_personhood_ring(chain);
    }

    // -- D6: payment classification ------------------------------------------

    #[test]
    fn a_memo_naming_only_our_accounts_is_matched() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let first = fund(&mut layer, PurseId::MAIN, 4);
        let savings =
            block_on(layer.create_purse(&storage, "Savings".to_string(), NOW)).expect("creates");
        let second = fund(&mut layer, savings, 3);

        let entries = vec![
            memo_for(PurseId::MAIN, first),
            // Across purses: a payee holds accounts in more than one namespace.
            memo_for(savings, second),
        ];

        assert_eq!(
            layer.classify_incoming_payment(&entries),
            PaymentClassification::Matched
        );
    }

    #[test]
    fn a_memo_naming_some_of_our_accounts_is_received() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let ours = fund(&mut layer, PurseId::MAIN, 4);

        let entries = vec![
            memo_for(PurseId::MAIN, ours),
            MemoEntry {
                sender_coin_account: CoinAccountId([1; 32]),
                recipient_account: CoinAccountId([0xab; 32]),
                derivation_index: CoinIndex(0),
            },
        ];

        assert_eq!(
            layer.classify_incoming_payment(&entries),
            PaymentClassification::Received,
            "half a payment is not a whole one"
        );
    }

    #[test]
    fn a_memo_naming_nothing_of_ours_is_unmatched() {
        let storage = MemStorage::default();
        let layer = layer(&storage);

        let entries = vec![MemoEntry {
            sender_coin_account: CoinAccountId([1; 32]),
            recipient_account: CoinAccountId([0xab; 32]),
            derivation_index: CoinIndex(0),
        }];

        assert_eq!(
            layer.classify_incoming_payment(&entries),
            PaymentClassification::Unmatched
        );
    }

    #[test]
    fn an_empty_memo_is_unmatched() {
        let storage = MemStorage::default();
        let layer = layer(&storage);

        assert_eq!(
            layer.classify_incoming_payment(&[]),
            PaymentClassification::Unmatched,
            "nothing was claimed, so nothing matches"
        );
    }

    #[test]
    fn classification_touches_nothing() {
        // §8.8: informational only. A memo must not be able to move a record or
        // start an operation, because it arrives from whoever sent it.
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let ours = fund(&mut layer, PurseId::MAIN, 4);
        let before = layer.store().coins_in(PurseId::MAIN);

        let _ = layer.classify_incoming_payment(&[memo_for(PurseId::MAIN, ours)]);

        assert_eq!(layer.store().coins_in(PurseId::MAIN), before);
        assert!(layer.store().open_operations().next().is_none());
    }

    /// A memo entry naming one of our own coin accounts.
    fn memo_for(purse: PurseId, index: CoinIndex) -> MemoEntry {
        MemoEntry {
            sender_coin_account: CoinAccountId([9; 32]),
            recipient_account: derivation::coin_account_id(&ENTROPY, purse, index)
                .expect("derives"),
            derivation_index: index,
        }
    }

    // -- D7: top-up ----------------------------------------------------------

    #[test]
    fn a_top_up_loads_one_entry_per_denomination_in_a_single_batch() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let chain = FakeChain::default();
        let rpc = chain.rpc();
        let metadata = metadata();
        let origin = Arc::new(TestFunding::new([0x21; 32]));

        // 24 cents is 16 + 8: two entries, one extrinsic.
        let started = layer
            .begin_top_up(PurseId::MAIN, Amount::from_cents(24), origin.clone(), NOW)
            .expect("the purse exists");

        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), started.handle, NOW))
            .expect("drives");

        assert_eq!(chain.submission_count(), 1, "one batched extrinsic");
        let entries = layer.store().entries_in(PurseId::MAIN);
        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0].exponent, exponent(4));
        assert_eq!(entries[1].exponent, exponent(3));
        let items: Vec<OperationStatus> = block_on(started.status.collect());
        assert!(matches!(items.last(), Some(OperationStatus::Done(_))));
    }

    #[test]
    fn a_top_up_is_signed_by_the_account_holding_the_asset() {
        // The layer holds nothing here: the value being converted is the caller's
        // until the pallet turns it into entries.
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let chain = FakeChain::default();
        let rpc = chain.rpc();
        let metadata = metadata();
        let origin = Arc::new(TestFunding::new([0x21; 32]));

        let started = layer
            .begin_top_up(PurseId::MAIN, Amount::from_cents(16), origin.clone(), NOW)
            .expect("the purse exists");
        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), started.handle, NOW))
            .expect("drives");

        assert_eq!(origin.signed(), 1, "the origin signed the extrinsic");
        assert_eq!(
            origin.authorized(),
            1,
            "and produced the value-transfer authorization the runtime gates on"
        );
        let submitted = &chain.submitted()[0];
        assert!(
            submitted
                .windows(32)
                .any(|window| window == origin.account().0),
            "the signing account appears in the extrinsic's address field"
        );
    }

    #[test]
    fn a_top_up_entry_carries_its_own_readiness_delay() {
        // §5.3: an entry usable the instant it is loaded would let an observer pair
        // the load with the unload that follows it.
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let origin = Arc::new(TestFunding::new([0x21; 32]));

        layer
            .begin_top_up(PurseId::MAIN, Amount::from_cents(16), origin, NOW)
            .expect("the purse exists");

        let entries = layer.store().entries_in(PurseId::MAIN);
        assert_eq!(entries.len(), 1);
        assert!(
            entries[0].ready_at >= NOW,
            "a fresh entry is not selectable before its delay"
        );
        assert!(
            entries[0].ready_at
                <= NOW.saturating_add(layer.params().recycler_entry_jitter_upper_bound),
            "and the delay is inside the configured bound"
        );
    }

    #[test]
    fn a_top_up_needing_more_entries_than_the_runtime_batches_is_refused() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let origin = Arc::new(TestFunding::new([0x21; 32]));
        // A cent count whose binary expansion is longer than MaxBatchUnpaidLoad.
        let awkward = Amount::from_cents((1 << 12) - 1);

        let refused = layer
            .begin_top_up(PurseId::MAIN, awkward, origin, NOW)
            .expect_err("twelve denominations exceed a batch of ten");

        assert!(
            refused.to_string().contains("batches at most"),
            "unexpected: {refused}"
        );
    }

    #[test]
    fn a_top_up_into_a_purse_that_does_not_exist_is_refused() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let origin = Arc::new(TestFunding::new([0x21; 32]));

        assert_eq!(
            layer
                .begin_top_up(PurseId(9), Amount::from_cents(16), origin, NOW)
                .expect_err("there is no such purse"),
            CoinageError::PurseNotFound(PurseId(9))
        );
    }

    #[test]
    fn a_refused_top_up_retires_the_entries_that_never_came() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let chain = FakeChain::new(Inclusion::Rejected);
        let rpc = chain.rpc();
        let metadata = metadata();
        let origin = Arc::new(TestFunding::new([0x21; 32]));

        let started = layer
            .begin_top_up(PurseId::MAIN, Amount::from_cents(16), origin, NOW)
            .expect("the purse exists");
        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), started.handle, NOW))
            .expect("drives");

        assert_eq!(
            layer.store().entries_in(PurseId::MAIN)[0].local,
            EntryLocalState::Consumed,
            "the entry that was never created is retired, index and all"
        );
        assert_eq!(
            layer
                .store()
                .balance(PurseId::MAIN, NOW)
                .expect("purse exists")
                .pending,
            Amount::ZERO,
            "and the purse does not claim value that never arrived"
        );
    }

    /// A funding origin that signs with a throwaway key and counts what it was
    /// asked for.
    struct TestFunding {
        keypair: schnorrkel::Keypair,
        signed: StdMutex<usize>,
        authorized: StdMutex<usize>,
    }

    impl TestFunding {
        fn new(seed: [u8; 32]) -> Self {
            let mini = schnorrkel::MiniSecretKey::from_bytes(&seed).expect("32 bytes");
            Self {
                keypair: mini.expand_to_keypair(schnorrkel::ExpansionMode::Ed25519),
                signed: StdMutex::new(0),
                authorized: StdMutex::new(0),
            }
        }

        fn account(&self) -> CoinAccountId {
            CoinAccountId(self.keypair.public.to_bytes())
        }

        fn signed(&self) -> usize {
            *self.signed.lock().unwrap()
        }

        fn authorized(&self) -> usize {
            *self.authorized.lock().unwrap()
        }
    }

    impl FundingOrigin for TestFunding {
        fn external_account(&self) -> CoinAccountId {
            self.account()
        }

        fn sign(&self, payload: &[u8]) -> [u8; 64] {
            *self.signed.lock().unwrap() += 1;
            self.keypair
                .sign_simple(
                    crate::host_logic::product_account::SR25519_SIGNING_CONTEXT,
                    payload,
                )
                .to_bytes()
        }

        fn authorize_value_transfer(&self, _message: &[u8; 32]) -> Option<[u8; 64]> {
            *self.authorized.lock().unwrap() += 1;
            Some([7u8; 64])
        }
    }

    // -- D8: wallet recovery from root entropy -------------------------------

    #[test]
    fn recovery_rebuilds_a_wallet_from_the_chain_alone() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let chain = FakeChain::default();
        let rpc = chain.rpc();
        let metadata = metadata();

        // A coin and an entry the chain holds under our derivation, with no local
        // record of either: durable state is gone.
        let account =
            derivation::coin_account_id(&ENTROPY, PurseId::MAIN, CoinIndex(0)).expect("derives");
        chain.set_storage(
            &storage::coins_by_owner_key(&account),
            chain_coin(exponent(4), CoinAge(2)),
        );
        let member_key =
            derivation::entry_member_key(&ENTROPY, PurseId::MAIN, EntryIndex(0)).expect("derives");
        let alias =
            crate::runtime::coinage::proof::recycler_alias(&ENTROPY, PurseId::MAIN, EntryIndex(0))
                .expect("derives");
        let mut members = vec![member_key];
        members.extend(fillers(15));
        chain.place_entry_in_ring(exponent(3), member_key, alias, ring(), &members, None);

        layer.set_recovery_limits_for_tests(4, 2);
        let mut events = layer.subscribe_events();
        let started = layer.begin_recovery(Vec::new()).expect("starts");

        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), started.handle, NOW))
            .expect("drives");

        assert_eq!(chain.submission_count(), 0, "recovery writes nothing");
        let coins = layer.store().coins_in(PurseId::MAIN);
        assert_eq!(coins.len(), 1);
        assert_eq!(coins[0].exponent, exponent(4));
        assert_eq!(coins[0].age, CoinAge(2));
        let entries = layer.store().entries_in(PurseId::MAIN);
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].exponent, exponent(3));
        // Observation ran over what the scan found, so the entry knows its ring.
        assert_eq!(entries[0].ring.map(|ring| ring.index), Some(ring().index));

        let published: Vec<LayerEvent> =
            core::iter::from_fn(|| futures::FutureExt::now_or_never(events.next()).flatten())
                .collect();
        assert!(
            published
                .iter()
                .any(|event| matches!(event, LayerEvent::CoinAvailable { .. })),
            "per-record discovery is observable: {published:?}"
        );
        assert!(
            published
                .iter()
                .any(|event| matches!(event, LayerEvent::EntryAllocated { .. }))
        );
        // Reconstruction ends with Resynced, so a subscriber can tell rebuilt
        // state from the live changes that follow. It comes after every restored
        // record and before the operation's own completion.
        let resynced = published
            .iter()
            .position(|event| matches!(event, LayerEvent::Resynced))
            .expect("reconstruction is closed off");
        let last_record = published
            .iter()
            .rposition(|event| {
                matches!(
                    event,
                    LayerEvent::CoinAvailable { .. } | LayerEvent::EntryAllocated { .. }
                )
            })
            .expect("records were restored");
        assert!(resynced > last_record, "{published:?}");

        let items: Vec<OperationStatus> = block_on(started.status.collect());
        assert_eq!(
            items.first(),
            Some(&OperationStatus::Preparing),
            "no extrinsic, so the status goes straight to terminal: {items:?}"
        );
        assert!(matches!(items.last(), Some(OperationStatus::Done(_))));
    }

    #[test]
    fn recovery_restores_a_named_purse_at_its_own_identifier() {
        // The identifier is the derivation namespace, so a recovered purse cannot
        // be given a fresh one.
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let chain = FakeChain::default();
        let rpc = chain.rpc();
        let metadata = metadata();
        let savings = PurseId(4);
        let account =
            derivation::coin_account_id(&ENTROPY, savings, CoinIndex(0)).expect("derives");
        chain.set_storage(
            &storage::coins_by_owner_key(&account),
            chain_coin(exponent(4), CoinAge(0)),
        );

        layer.set_recovery_limits_for_tests(4, 2);
        let started = layer.begin_recovery(vec![savings]).expect("starts");
        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), started.handle, NOW))
            .expect("drives");

        assert!(layer.store().purse(savings).is_some());
        assert_eq!(layer.store().coins_in(savings).len(), 1);
        // And a purse created afterwards cannot collide with the restored one.
        let fresh =
            block_on(layer.create_purse(&storage, "Later".to_string(), NOW)).expect("creates");
        assert!(fresh.0 > savings.0, "{fresh:?}");
    }

    #[test]
    fn an_empty_wallet_recovers_to_nothing_and_still_says_it_finished() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let chain = FakeChain::default();
        let rpc = chain.rpc();
        let metadata = metadata();

        layer.set_recovery_limits_for_tests(4, 2);
        let started = layer.begin_recovery(Vec::new()).expect("starts");
        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), started.handle, NOW))
            .expect("drives");

        assert!(layer.store().coins_in(PurseId::MAIN).is_empty());
        let items: Vec<OperationStatus> = block_on(started.status.collect());
        assert!(matches!(items.last(), Some(OperationStatus::Done(_))));
    }

    #[test]
    fn extending_a_scan_reaches_records_the_gap_limit_hid() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);
        let chain = FakeChain::default();
        let rpc = chain.rpc();
        let metadata = metadata();
        // Just past a narrow window's reach from zero: 4 * 2 batches of 4.
        layer.set_recovery_limits_for_tests(4, 2);
        let far = CoinIndex(20);
        let account = derivation::coin_account_id(&ENTROPY, PurseId::MAIN, far).expect("derives");
        chain.set_storage(
            &storage::coins_by_owner_key(&account),
            chain_coin(exponent(4), CoinAge(0)),
        );

        let first = layer.begin_recovery(Vec::new()).expect("starts");
        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), first.handle, NOW))
            .expect("drives");
        assert!(
            layer.store().coins_in(PurseId::MAIN).is_empty(),
            "the gap swallowed it"
        );

        let extended = layer
            .begin_extend_scan(PurseId::MAIN, CoinIndex(16), EntryIndex(0))
            .expect("the purse exists");
        block_on(layer.drive_operation(&storage, &context(&rpc, &metadata), extended.handle, NOW))
            .expect("drives");

        assert_eq!(
            layer.store().coins_in(PurseId::MAIN)[0].index,
            far,
            "resuming past the gap finds it"
        );
    }

    #[test]
    fn extending_a_scan_of_a_purse_that_does_not_exist_is_refused() {
        let storage = MemStorage::default();
        let mut layer = layer(&storage);

        assert_eq!(
            layer
                .begin_extend_scan(PurseId(9), CoinIndex(0), EntryIndex(0))
                .expect_err("there is no such purse"),
            CoinageError::PurseNotFound(PurseId(9))
        );
    }

    // -- chain-state fixtures ------------------------------------------------

    /// Unrelated but *valid* ring members, to pad a ring out.
    ///
    /// Filler bytes would not do: the prover reconstructs the ring commitment
    /// from the member list, so every entry has to be a real bandersnatch key.
    fn fillers(count: u8) -> Vec<[u8; 32]> {
        use verifiable::GenerateVerifiable;
        use verifiable::ring::bandersnatch::BandersnatchVrfVerifiable;

        (1..=count)
            .map(|byte| {
                let secret = BandersnatchVrfVerifiable::new_secret([byte; 32]);
                BandersnatchVrfVerifiable::member_from_secret(&secret)
            })
            .collect()
    }

    /// `AccountInfo` with a free balance, for the fee account.
    fn account_info(free: u128) -> Vec<u8> {
        let mut encoded = 0u32.encode();
        encoded.extend(0u32.encode());
        encoded.extend(1u32.encode());
        encoded.extend(0u32.encode());
        encoded.extend(free.encode());
        encoded.extend(0u128.encode());
        encoded.extend(0u128.encode());
        encoded.extend(0u128.encode());
        encoded
    }

    /// The LitePeople ring, so a free unload token can be proven.
    ///
    /// A different ring and a different key from any recycler entry: the token
    /// proves personhood, not ownership of the entries being unloaded.
    fn set_personhood_ring(chain: &FakeChain) {
        let personhood = crate::runtime::statement_allowance::proof::member_key(
            crate::runtime::statement_allowance::bandersnatch_entropy(&ENTROPY),
        );
        let mut members = vec![personhood];
        members.extend(fillers(9));
        let members = &members[..];
        use sp_crypto_hashing::{blake2_128, twox_64, twox_128};

        let identifier: &[u8; 32] = b"pop:polkadot.network/people-lite";
        let concat = |x: &[u8]| [blake2_128(x).as_slice(), x].concat();
        let twox_concat = |x: &[u8]| [twox_64(x).as_slice(), x].concat();

        chain.set_storage(
            &[
                twox_128(b"Members").as_slice(),
                twox_128(b"Collections").as_slice(),
                identifier.as_slice(),
            ]
            .concat(),
            collection_info(9),
        );
        chain.set_storage(
            &[
                twox_128(b"Members").as_slice(),
                twox_128(b"CurrentRingIndex").as_slice(),
                identifier.as_slice(),
            ]
            .concat(),
            0u32.encode(),
        );
        chain.set_storage(
            &[
                twox_128(b"Members").as_slice(),
                twox_128(b"RingKeys").as_slice(),
                identifier.as_slice(),
                &concat(&0u32.to_le_bytes()),
                &twox_concat(&0u32.to_le_bytes()),
            ]
            .concat(),
            ring_page(members),
        );
        chain.set_storage(
            &[
                twox_128(b"Members").as_slice(),
                twox_128(b"RingKeysStatus").as_slice(),
                identifier.as_slice(),
                &concat(&0u32.to_le_bytes()),
            ]
            .concat(),
            ring_status(members.len() as u32, None),
        );
    }
}
