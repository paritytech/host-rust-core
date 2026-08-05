//! Bringing the layer up: chain constants, the fee account, and the store.
//!
//! `coinage-layer.md` §6.7 and §13. Two things happen here that must happen
//! before any operation is accepted.
//!
//! **The runtime is checked.** Chain-enforced limits are read from metadata and
//! validated, so an unsupported runtime is refused at connection rather than
//! discovered at the first rejected extrinsic. Two of the ten constants are not
//! discoverable and arrive as configuration instead; where a configured value
//! *is* observable, disagreement is a hard failure rather than something to
//! reconcile silently.
//!
//! **The store is loaded.** From durable storage if it exists, otherwise fresh
//! with only the main purse, which exists by construction once entropy is
//! present.

use core::time::Duration;
use std::collections::BTreeMap;
use std::sync::Arc;

use futures::channel::mpsc;
use futures::stream::BoxStream;
use parity_scale_codec::Decode;
use truapi_platform::CoreStorage;

use crate::host_logic::coinage::chain_constants::CoinageChainConstants;
use crate::host_logic::coinage::derivation;
use crate::host_logic::coinage::error::CoinageError;
use crate::host_logic::coinage::event::LayerEvent;
use crate::host_logic::coinage::operation::OperationStatus;
use crate::host_logic::coinage::params::CoinageParameters;
use crate::host_logic::coinage::purse::PurseBalance;
use crate::host_logic::coinage::store::CoinageStore;
use crate::host_logic::coinage::types::{
    CoinAccountId, CoinAge, CoinSecret, OperationHandle, PurseId, Timestamp,
};
use crate::runtime::coinage::execute::{
    Completion, ExportedCoin, MemoCallback, OffloadRequest, RecoveryRequest,
};
use crate::runtime::coinage::extrinsic::FundingOrigin;
use crate::runtime::coinage::persistence;
use crate::runtime::coinage::plan::OperationProgram;
use crate::runtime::coinage::subscription::CoinageSubscriptions;
use crate::runtime::statement_allowance::extension::Metadata;

/// Pallet whose constants describe the layer's limits.
const PALLET: &str = "Coinage";

/// Values the layer must be told because the deployed runtime does not publish
/// them, plus the local naming choice for the main purse.
///
/// The first two are exactly the constants guarding the two fund-loss paths —
/// coins ageing out, and entries expiring in a ring — so a deployment that gets
/// them wrong loses value silently. See `coinage-layer.md` Appendix A.0.
///
/// The two paid-token values cannot lose value, but a wrong period spends a join
/// fee on a token that proves against the wrong collection.
#[derive(Debug, Clone)]
pub struct CoinageConfig {
    /// `MaximumAge`: declared without `#[pallet::constant]`, so absent from
    /// metadata on every runtime.
    pub maximum_age: CoinAge,
    /// `RecyclerExpirationTime`: marked `#[pallet::constant]` in the pallet
    /// source but absent from the deployed runtime's metadata.
    pub recycler_expiration_time: Duration,
    /// `PaidUnloadTokenTimePeriod`: as above. Distinct from the free-token
    /// period, and longer on the reference runtime.
    pub paid_unload_token_period: Duration,
    /// `PaidUnloadTokenRingExpirationTime`: as above.
    pub paid_unload_token_ring_expiration: Duration,
    /// Display name for the main purse on first run.
    pub main_purse_name: String,
}

impl Default for CoinageConfig {
    /// The `next-people-paseo` values.
    fn default() -> Self {
        Self {
            maximum_age: CoinAge(16),
            recycler_expiration_time: Duration::from_secs(90 * 24 * 60 * 60),
            paid_unload_token_period: Duration::from_secs(3 * 24 * 60 * 60),
            paid_unload_token_ring_expiration: Duration::from_secs(4 * 24 * 60 * 60),
            main_purse_name: "Main".to_string(),
        }
    }
}

/// A brought-up coinage layer: validated constants, the fee account, and the
/// record store.
///
/// Holds the root entropy, so it is never `Debug`-printed in full and must not
/// be logged. Chain access and the operation machinery attach to this in later
/// layers; this type owns what every one of them needs.
pub struct CoinageLayer {
    entropy: Vec<u8>,
    constants: CoinageChainConstants,
    params: CoinageParameters,
    fee_account: CoinAccountId,
    store: CoinageStore,
    subscriptions: Arc<CoinageSubscriptions>,
    /// What a wallet-recovery scan was asked to walk, by operation.
    recoveries: BTreeMap<OperationHandle, RecoveryRequest>,
    /// Who signs for a top-up's incoming asset, by operation.
    ///
    /// Beside the program rather than inside it: a signer is not data, and the
    /// account it speaks for is not one this layer holds.
    funding: BTreeMap<OperationHandle, Arc<dyn FundingOrigin + Send + Sync>>,
    /// What an external offload was asked to do, by operation.
    ///
    /// An offload re-plans between phases, so it has a request rather than a
    /// program. Not durable: a restart before the first broadcast is a cancel, and
    /// after one, recovery resolves the log.
    offloads: BTreeMap<OperationHandle, OffloadRequest>,
    /// Sinks for the coins an export hands out, by operation.
    exports: BTreeMap<OperationHandle, mpsc::UnboundedSender<ExportedCoin>>,
    /// Secrets an import was handed, by operation.
    ///
    /// Dropped as soon as the operation's transactions have been broadcast: §8.5
    /// requires the layer not to retain them, and holding them for longer would
    /// keep spendable material alive for no purpose.
    import_secrets: BTreeMap<OperationHandle, Vec<CoinSecret>>,
    /// Work to apply once an operation's transactions have definitely settled.
    ///
    /// Not durable, for the same reason as the programs: an operation that never
    /// broadcast has nothing to complete, and one that did is resolved by recovery
    /// from the log rather than from a local intention.
    completions: BTreeMap<OperationHandle, Completion>,
    /// Memo callbacks awaiting their transactions' inclusion, by operation.
    ///
    /// Alongside the programs rather than inside them because a callback is not
    /// data: it cannot be compared, printed, or persisted.
    memos: BTreeMap<OperationHandle, MemoCallback>,
    /// Transactions planned but not yet submitted, by operation.
    ///
    /// Deliberately not durable. §7.8 makes a restart while preparing equivalent
    /// to a cancel, so a program that never reached a broadcast has nothing worth
    /// surviving: the records it named are still locked in the persisted store and
    /// `reconcile_after_restart` releases them.
    programs: BTreeMap<OperationHandle, OperationProgram>,
}

impl core::fmt::Debug for CoinageLayer {
    /// Deliberately omits the entropy and the records.
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.debug_struct("CoinageLayer")
            .field("purses", &self.store.purses().count())
            .field("fee_account", &hex::encode(self.fee_account.0))
            .finish_non_exhaustive()
    }
}

impl CoinageLayer {
    /// Read the runtime's constants, derive the fee account, and load the store.
    ///
    /// Fails rather than degrades: an unsupported runtime, a constant the
    /// runtime should publish but does not, or an undecodable store all stop
    /// the layer from coming up.
    pub async fn initialize<S: CoreStorage + ?Sized>(
        storage: &S,
        metadata: &Metadata,
        entropy: Vec<u8>,
        config: &CoinageConfig,
    ) -> Result<Self, CoinageError> {
        let constants = read_chain_constants(metadata, config)?;
        constants.validate()?;

        let fee_account = derivation::fee_account_id(&entropy)?;
        let store = persistence::load(storage, &config.main_purse_name).await?;

        Ok(Self {
            entropy,
            constants,
            params: CoinageParameters::default(),
            fee_account,
            store,
            subscriptions: CoinageSubscriptions::new(),
            recoveries: BTreeMap::new(),
            funding: BTreeMap::new(),
            offloads: BTreeMap::new(),
            exports: BTreeMap::new(),
            import_secrets: BTreeMap::new(),
            completions: BTreeMap::new(),
            memos: BTreeMap::new(),
            programs: BTreeMap::new(),
        })
    }

    /// The runtime's chain-enforced limits.
    pub const fn constants(&self) -> &CoinageChainConstants {
        &self.constants
    }

    /// The layer's policy tunables.
    pub const fn params(&self) -> &CoinageParameters {
        &self.params
    }

    /// The account paying unload fees.
    pub const fn fee_account(&self) -> CoinAccountId {
        self.fee_account
    }

    /// Root entropy, for the derivation calls that need it.
    pub fn entropy(&self) -> &[u8] {
        &self.entropy
    }

    /// The record store.
    pub const fn store(&self) -> &CoinageStore {
        &self.store
    }

    /// The record store, mutably. Every mutation must be followed by
    /// [`Self::publish_and_persist`] before the layer yields to the caller.
    pub const fn store_mut(&mut self) -> &mut CoinageStore {
        &mut self.store
    }

    /// Remember the transactions an operation still has to submit.
    pub(crate) fn register_program(&mut self, handle: OperationHandle, program: OperationProgram) {
        self.programs.insert(handle, program);
    }

    /// Remember what a recovery scan should walk.
    pub(crate) fn register_recovery(&mut self, handle: OperationHandle, request: RecoveryRequest) {
        self.recoveries.insert(handle, request);
    }

    /// Take a recovery's request, leaving nothing behind.
    pub(crate) fn take_recovery(&mut self, handle: OperationHandle) -> Option<RecoveryRequest> {
        self.recoveries.remove(&handle)
    }

    /// Remember who signs for a top-up.
    pub(crate) fn register_funding_origin(
        &mut self,
        handle: OperationHandle,
        origin: Arc<dyn FundingOrigin + Send + Sync>,
    ) {
        self.funding.insert(handle, origin);
    }

    /// The funding origin for an operation, if it has one.
    pub(crate) fn funding_origin(
        &self,
        handle: OperationHandle,
    ) -> Option<Arc<dyn FundingOrigin + Send + Sync>> {
        self.funding.get(&handle).cloned()
    }

    /// Forget a top-up's funding origin.
    pub(crate) fn forget_funding_origin(&mut self, handle: OperationHandle) {
        self.funding.remove(&handle);
    }

    /// Remember what an offload was asked to do.
    pub(crate) fn register_offload(&mut self, handle: OperationHandle, request: OffloadRequest) {
        self.offloads.insert(handle, request);
    }

    /// Take an offload's request, leaving nothing behind.
    pub(crate) fn take_offload(&mut self, handle: OperationHandle) -> Option<OffloadRequest> {
        self.offloads.remove(&handle)
    }

    /// Remember where an export's coins should be delivered.
    pub(crate) fn register_export(
        &mut self,
        handle: OperationHandle,
        sender: mpsc::UnboundedSender<ExportedCoin>,
    ) {
        self.exports.insert(handle, sender);
    }

    /// Hand one exported coin to whoever holds the export's stream.
    pub(crate) fn send_export(&mut self, handle: OperationHandle, coin: ExportedCoin) {
        if let Some(sender) = self.exports.get(&handle) {
            let _ = sender.unbounded_send(coin);
        }
    }

    /// Close an export's stream: no further coin can be emitted for it.
    pub(crate) fn close_exports(&mut self, handle: OperationHandle) {
        self.exports.remove(&handle);
    }

    /// Remember the secrets an import was handed.
    pub(crate) fn register_import_secrets(
        &mut self,
        handle: OperationHandle,
        secrets: Vec<CoinSecret>,
    ) {
        self.import_secrets.insert(handle, secrets);
    }

    /// One of an import's supplied secrets, by position.
    pub(crate) fn import_secret(
        &self,
        handle: OperationHandle,
        position: usize,
    ) -> Option<&CoinSecret> {
        self.import_secrets.get(&handle)?.get(position)
    }

    /// Drop every secret an import was handed.
    pub(crate) fn forget_import_secrets(&mut self, handle: OperationHandle) {
        self.import_secrets.remove(&handle);
    }

    /// Remember what to do once an operation's transactions have settled.
    pub(crate) fn register_completion(&mut self, handle: OperationHandle, completion: Completion) {
        self.completions.insert(handle, completion);
    }

    /// Take an operation's completion, leaving nothing behind.
    pub(crate) fn take_completion(&mut self, handle: OperationHandle) -> Option<Completion> {
        self.completions.remove(&handle)
    }

    /// Remember a memo callback to invoke as the operation's transactions land.
    pub(crate) fn register_memo(&mut self, handle: OperationHandle, memo: MemoCallback) {
        self.memos.insert(handle, memo);
    }

    /// The memo callback for an operation, if the caller supplied one.
    pub(crate) fn memo_of(&self, handle: OperationHandle) -> Option<&MemoCallback> {
        self.memos.get(&handle)
    }

    /// Forget an operation's memo callback, once it can no longer fire.
    pub(crate) fn forget_memo(&mut self, handle: OperationHandle) {
        self.memos.remove(&handle);
    }

    /// Take an operation's program, leaving nothing behind.
    ///
    /// Taken rather than borrowed so driving an operation twice cannot submit its
    /// transactions twice.
    pub(crate) fn take_program(&mut self, handle: OperationHandle) -> Option<OperationProgram> {
        self.programs.remove(&handle)
    }

    /// Whether an operation still has transactions waiting to be submitted.
    pub fn has_pending_program(&self, handle: OperationHandle) -> bool {
        self.programs.contains_key(&handle)
    }

    /// Fix the jitter upper bound, so a test can make a fresh entry usable at once.
    ///
    /// Production draws a delay in `[0, bound]` per new entry (§5.3); a test that
    /// wants the next phase to see the entry sets the bound to zero.
    #[cfg(test)]
    pub(crate) fn set_jitter_for_tests(&mut self, bound: Duration) {
        self.params.recycler_entry_jitter_upper_bound = bound;
    }

    /// Shrink the recovery scan's window, so a test does not derive thousands of
    /// keys to prove one behaviour.
    #[cfg(test)]
    pub(crate) fn set_recovery_limits_for_tests(&mut self, batch_size: u32, gap_limit: u32) {
        self.params.recovery_batch_size = batch_size;
        self.params.recovery_gap_limit = gap_limit;
    }

    /// Publish the store's pending events to the layer's subscribers, then write
    /// the store back.
    ///
    /// `now` is what the balance streams are reprojected against; see
    /// [`CoinageSubscriptions`] for why a balance cannot ride on an event.
    pub async fn publish_and_persist<S>(
        &mut self,
        storage: &S,
        now: Timestamp,
    ) -> Result<(), CoinageError>
    where
        S: CoreStorage + ?Sized,
    {
        let subscriptions = self.subscriptions.clone();
        persistence::publish_and_persist(storage, &mut self.store, move |events, store| {
            subscriptions.publish(&events, store, now);
        })
        .await
    }

    /// Reproject the balance streams without a mutation to publish.
    ///
    /// For the driver's clock tick: a jitter delay elapsing or a chain lock
    /// expiring changes a purse's balance while every record stays as it was.
    pub fn refresh_subscriptions(&self, now: Timestamp) {
        self.subscriptions.refresh(&self.store, now);
    }

    /// Subscribe to the layer's event stream (§8.9).
    pub fn subscribe_events(&self) -> BoxStream<'static, LayerEvent> {
        self.subscriptions.subscribe_events()
    }

    /// Subscribe to a purse's balance, current value first (§8.9).
    pub fn subscribe_purse_balance(
        &self,
        purse: PurseId,
        now: Timestamp,
    ) -> Result<BoxStream<'static, PurseBalance>, CoinageError> {
        self.subscriptions
            .subscribe_purse_balance(&self.store, purse, now)
    }

    /// Subscribe to an operation's status stream (§7.2).
    pub fn subscribe_operation_status(
        &self,
        handle: OperationHandle,
    ) -> Result<BoxStream<'static, OperationStatus>, CoinageError> {
        self.subscriptions
            .subscribe_operation_status(&self.store, handle)
    }
}

/// Assemble the runtime's constants from metadata plus the four it cannot
/// publish.
pub fn read_chain_constants(
    metadata: &Metadata,
    config: &CoinageConfig,
) -> Result<CoinageChainConstants, CoinageError> {
    let constants = CoinageChainConstants {
        minimum_exponent: required(metadata, "MinimumExponent")?,
        maximum_exponent: required(metadata, "MaximumExponent")?,
        maximum_age: agreed(metadata, "MaximumAge", config.maximum_age, |value: u16| {
            CoinAge(value)
        })?,
        max_split_outputs: required(metadata, "MaxSplitOutputs")?,
        max_consolidation: required(metadata, "MaxConsolidation")?,
        recycler_expiration_time: agreed(
            metadata,
            "RecyclerExpirationTime",
            config.recycler_expiration_time,
            |secs: u32| Duration::from_secs(u64::from(secs)),
        )?,
        unload_token_period: required::<u32>(metadata, "UnloadTokenTimePeriodPeopleLitePeople")
            .map(|secs| Duration::from_secs(u64::from(secs)))?,
        paid_unload_token_period: agreed(
            metadata,
            "PaidUnloadTokenTimePeriod",
            config.paid_unload_token_period,
            |secs: u32| Duration::from_secs(u64::from(secs)),
        )?,
        paid_unload_token_ring_expiration: agreed(
            metadata,
            "PaidUnloadTokenRingExpirationTime",
            config.paid_unload_token_ring_expiration,
            |secs: u32| Duration::from_secs(u64::from(secs)),
        )?,
        max_free_unload_tokens_per_period: required(metadata, "MaxFreeUnloadTokensPerTimePeriod")?,
        max_batch_unpaid_load: required(metadata, "MaxBatchUnpaidLoad")?,
        underlying_asset_unit: required(metadata, "UnderlyingAssetUnit")?,
        coin_failure_lock_period: required::<u64>(metadata, "CoinFailureLockPeriod")
            .map(Duration::from_secs)?,
    };

    Ok(constants)
}

/// Read a constant the runtime is expected to publish.
fn required<T: Decode>(metadata: &Metadata, name: &str) -> Result<T, CoinageError> {
    let bytes = metadata.constant(PALLET, name).ok_or_else(|| {
        CoinageError::Internal(format!(
            "runtime does not publish {PALLET}.{name}; this layer cannot operate against it"
        ))
    })?;
    T::decode(&mut &bytes[..])
        .map_err(|error| CoinageError::Internal(format!("decoding {PALLET}.{name}: {error}")))
}

/// Take a configured value, but refuse to disagree with the runtime.
///
/// These constants are absent from the deployed runtime, so configuration is the
/// only source. A newer runtime that does publish one must agree with what the
/// deployment was told: two of them drive a sweep whose whole job is to beat a
/// chain deadline, and being quietly wrong about either destroys value.
fn agreed<R, T>(
    metadata: &Metadata,
    name: &str,
    configured: T,
    convert: impl Fn(R) -> T,
) -> Result<T, CoinageError>
where
    R: Decode,
    T: PartialEq + core::fmt::Debug,
{
    let Some(bytes) = metadata.constant(PALLET, name) else {
        return Ok(configured);
    };
    let observed = R::decode(&mut &bytes[..])
        .map_err(|error| CoinageError::Internal(format!("decoding {PALLET}.{name}: {error}")))
        .map(convert)?;

    if observed == configured {
        Ok(configured)
    } else {
        Err(CoinageError::Internal(format!(
            "{PALLET}.{name} is configured as {configured:?} but the runtime reports {observed:?}"
        )))
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;
    use std::sync::Mutex;

    use parity_scale_codec::Encode;
    use truapi::v01;
    use truapi_platform::CoreStorageKey;

    use crate::host_logic::coinage::chain_constants::next_people_paseo;
    use crate::host_logic::coinage::types::PurseId;

    use super::*;

    const FIXTURE: &[u8] = include_bytes!("../../../tests/fixtures/paseo-next-v2-metadata.scale");

    fn metadata() -> Metadata {
        Metadata::decode(FIXTURE).expect("the fixture decodes")
    }

    #[derive(Default)]
    struct MemStorage(Mutex<HashMap<Vec<u8>, Vec<u8>>>);

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

    const ENTROPY: [u8; 32] = [7; 32];
    const NOW: Timestamp = Timestamp(1_000_000);

    #[test]
    fn the_deployed_runtime_yields_the_reference_constants() {
        // The fixture is a real paseo-next runtime, so this pins the reader
        // against the same values `coinage_chain_agreement` confirms live.
        let read = read_chain_constants(&metadata(), &CoinageConfig::default()).expect("reads");

        assert_eq!(read, next_people_paseo());
        assert_eq!(read.validate(), Ok(()));
    }

    #[test]
    fn configuration_supplies_what_the_runtime_does_not_publish() {
        // `MaximumAge` is absent from this runtime's metadata, so the
        // configured value is the only source and is taken verbatim.
        let config = CoinageConfig {
            maximum_age: CoinAge(99),
            ..CoinageConfig::default()
        };

        let read = read_chain_constants(&metadata(), &config).expect("reads");

        assert_eq!(read.maximum_age, CoinAge(99));
        assert!(
            metadata().constant(PALLET, "MaximumAge").is_none(),
            "the premise: this runtime really does not publish it"
        );
    }

    #[test]
    fn a_disagreement_between_config_and_runtime_is_fatal() {
        let observed: Result<Duration, _> = agreed(
            &metadata(),
            "CoinFailureLockPeriod",
            Duration::from_secs(60),
            |secs: u64| Duration::from_secs(secs),
        );
        assert_eq!(observed.expect("agrees"), Duration::from_secs(60));

        let mismatch: Result<Duration, _> = agreed(
            &metadata(),
            "CoinFailureLockPeriod",
            Duration::from_secs(5),
            |secs: u64| Duration::from_secs(secs),
        );
        assert!(
            mismatch.is_err(),
            "a runtime that contradicts configuration must stop the layer"
        );
    }

    #[test]
    fn a_missing_required_constant_stops_the_layer() {
        let absent: Result<u32, _> = required(&metadata(), "DefinitelyNotAConstant");

        assert!(absent.is_err());
    }

    #[test]
    fn initialize_derives_the_fee_account_and_loads_the_store() {
        let storage = MemStorage::default();

        let layer = block_on(CoinageLayer::initialize(
            &storage,
            &metadata(),
            ENTROPY.to_vec(),
            &CoinageConfig::default(),
        ))
        .expect("initializes");

        assert_eq!(layer.store().purses().count(), 1);
        assert!(layer.store().purse(PurseId::MAIN).is_some());
        assert_eq!(
            layer.fee_account(),
            derivation::fee_account_id(&ENTROPY).expect("derives")
        );
        assert_eq!(layer.constants(), &next_people_paseo());
    }

    #[test]
    fn initialize_reloads_a_persisted_store() {
        let storage = MemStorage::default();
        let mut layer = block_on(CoinageLayer::initialize(
            &storage,
            &metadata(),
            ENTROPY.to_vec(),
            &CoinageConfig::default(),
        ))
        .expect("initializes");
        let savings = layer.store_mut().create_purse("Savings".to_string());
        block_on(layer.publish_and_persist(&storage, NOW)).expect("persists");

        let reopened = block_on(CoinageLayer::initialize(
            &storage,
            &metadata(),
            ENTROPY.to_vec(),
            &CoinageConfig::default(),
        ))
        .expect("initializes");

        assert_eq!(reopened.store().purses().count(), 2);
        assert!(reopened.store().purse(savings).is_some());
    }

    #[test]
    fn persisting_publishes_to_the_layers_own_subscribers() {
        use futures::{FutureExt, StreamExt};

        let storage = MemStorage::default();
        let mut layer = block_on(CoinageLayer::initialize(
            &storage,
            &metadata(),
            ENTROPY.to_vec(),
            &CoinageConfig::default(),
        ))
        .expect("initializes");
        let mut events = layer.subscribe_events();
        let mut balances = layer
            .subscribe_purse_balance(PurseId::MAIN, NOW)
            .expect("purse exists");
        let _ = block_on(balances.next());

        let savings = layer.store_mut().create_purse("Savings".to_string());
        block_on(layer.publish_and_persist(&storage, NOW)).expect("persists");

        assert_eq!(
            block_on(events.next()),
            Some(LayerEvent::PurseCreated {
                purse: savings,
                name: "Savings".to_string(),
            })
        );
        // The new purse leaves the main purse's balance where it was.
        assert!(balances.next().now_or_never().is_none());
    }

    #[test]
    fn the_debug_rendering_never_carries_entropy() {
        let storage = MemStorage::default();
        let layer = block_on(CoinageLayer::initialize(
            &storage,
            &metadata(),
            ENTROPY.to_vec(),
            &CoinageConfig::default(),
        ))
        .expect("initializes");

        let rendered = format!("{layer:?}");

        assert!(!rendered.contains(&hex::encode(ENTROPY)));
        assert!(!rendered.contains("07070707"));
    }
}
