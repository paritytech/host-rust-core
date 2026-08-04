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

use parity_scale_codec::Decode;
use truapi_platform::CoreStorage;

use crate::host_logic::coinage::chain_constants::CoinageChainConstants;
use crate::host_logic::coinage::derivation;
use crate::host_logic::coinage::error::CoinageError;
use crate::host_logic::coinage::event::LayerEvent;
use crate::host_logic::coinage::params::CoinageParameters;
use crate::host_logic::coinage::store::CoinageStore;
use crate::host_logic::coinage::types::{CoinAccountId, CoinAge};
use crate::runtime::coinage::persistence;
use crate::runtime::statement_allowance::extension::Metadata;

/// Pallet whose constants describe the layer's limits.
const PALLET: &str = "Coinage";

/// Values the layer must be told because the deployed runtime does not publish
/// them, plus the local naming choice for the main purse.
///
/// The two constants here are exactly the ones guarding the two fund-loss paths
/// — coins ageing out, and entries expiring in a ring — so a deployment that
/// gets them wrong loses value silently. See `coinage-layer.md` Appendix A.0.
#[derive(Debug, Clone)]
pub struct CoinageConfig {
    /// `MaximumAge`: declared without `#[pallet::constant]`, so absent from
    /// metadata on every runtime.
    pub maximum_age: CoinAge,
    /// `RecyclerExpirationTime`: marked `#[pallet::constant]` in the pallet
    /// source but absent from the deployed runtime's metadata.
    pub recycler_expiration_time: Duration,
    /// Display name for the main purse on first run.
    pub main_purse_name: String,
}

impl Default for CoinageConfig {
    /// The `next-people-paseo` values.
    fn default() -> Self {
        Self {
            maximum_age: CoinAge(16),
            recycler_expiration_time: Duration::from_secs(90 * 24 * 60 * 60),
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

    /// Publish the store's pending events, then write it back.
    pub async fn publish_and_persist<S, P>(
        &mut self,
        storage: &S,
        publish: P,
    ) -> Result<(), CoinageError>
    where
        S: CoreStorage + ?Sized,
        P: FnOnce(Vec<LayerEvent>),
    {
        persistence::publish_and_persist(storage, &mut self.store, publish).await
    }
}

/// Assemble the runtime's constants from metadata plus the two it cannot
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
        max_free_unload_tokens_per_period: required(metadata, "MaxFreeUnloadTokensPerTimePeriod")?,
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
/// These two constants are absent from the deployed runtime, so configuration
/// is the only source. A newer runtime that does publish one must agree with
/// what the deployment was told, because both values drive a sweep whose whole
/// job is to beat a chain deadline — being quietly wrong about either destroys
/// value.
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
        block_on(layer.publish_and_persist(&storage, |_| {})).expect("persists");

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
