//! Ledger and driver for automatic statement-store allowance renewal.
//!
//! The ledger records which accounts this signing host promised to keep
//! allowed, as derivation recipes where possible so entries stay valid when
//! the host rotates to a new root entropy. The driver resolves them against
//! the active session and runs the chain-pure pass in
//! `statement_allowance::renewal`, either once (`renew_now`) or on a periodic
//! tick (`start_renewal_loop`).

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use futures::lock::Mutex;
use parity_scale_codec::{Decode, Encode};
use tracing::{debug, info, warn};
use truapi_platform::{CoreStorage, CoreStorageKey};

use super::SigningHost;
use super::sso_responder::current_unix_secs;
use crate::host_logic::product_account::{
    derive_lite_person_ring_vrf_entropy, derive_root_keypair_from_entropy, derive_sr25519_hard_path,
};
use crate::runtime::RuntimeServices;
use crate::runtime::statement_allowance::renewal::{
    RenewalChainContext, ResolvedRenewalTarget, StatementRenewalReport, next_tick_delay,
    renew_targets,
};
use crate::runtime::statement_allowance::{
    self, fetch_chain_state, fetch_metadata, find_including_ring,
};

/// Fallback tick delay when the system clock is unusable.
const CLOCK_FAILURE_TICK_DELAY: Duration = Duration::from_secs(3_600);

/// A statement-store account the signing host promised to keep renewed.
///
/// Entropy-derived variants are recipes, not raw account ids, so the ledger
/// survives root-entropy rotation (the CLI rotates auto-managed accounts on
/// slot exhaustion).
#[derive(Clone, Debug, PartialEq, Eq, Encode, Decode)]
pub enum StatementRenewalTarget {
    /// `//allowance//statement-store//{product_id}` from the active root entropy.
    ProductStatementAllowance {
        /// Product the allowance account belongs to.
        product_id: String,
    },
    /// `//wallet//sso` from the active root entropy.
    WalletSso,
    /// A fixed account, e.g. a pairing peer's device statement key.
    Account {
        /// Account to keep allowed.
        account_id: [u8; 32],
        /// Human-readable name used in logs and reports.
        label: String,
    },
}

/// One persisted ledger entry.
///
/// A derivation recipe resolves under whatever root entropy is active, so it
/// carries no owner and keeps working across a rotation. A raw account id does
/// not re-derive, so it records the root public key that promised it and is
/// ignored under any other identity: without that, a later account would spend
/// its own slot-table capacity keeping a previous account's peer allowed.
#[derive(Clone, Debug, PartialEq, Eq, Encode, Decode)]
struct LedgerEntry {
    target: StatementRenewalTarget,
    owner: Option<[u8; 32]>,
}

impl LedgerEntry {
    /// Record `target` under `owner`, which only raw account ids retain.
    fn new(target: StatementRenewalTarget, owner: [u8; 32]) -> Self {
        let owner = match &target {
            StatementRenewalTarget::Account { .. } => Some(owner),
            StatementRenewalTarget::ProductStatementAllowance { .. }
            | StatementRenewalTarget::WalletSso => None,
        };
        Self { target, owner }
    }

    /// Whether this entry belongs to the identity rooted at `owner`.
    fn is_owned_by(&self, owner: [u8; 32]) -> bool {
        self.owner.is_none_or(|recorded| recorded == owner)
    }
}

/// Root public key of the identity rooted at `entropy`, used to own raw ledger
/// entries.
fn owner_key(entropy: &[u8]) -> Result<[u8; 32], String> {
    derive_root_keypair_from_entropy(entropy)
        .map(|pair| pair.public.to_bytes())
        .map_err(|err| err.to_string())
}

/// Renewal coordination state owned by [`SigningHost`].
#[derive(Default)]
pub(super) struct RenewalState {
    /// Serializes slot registrations between the renewal pass and on-demand
    /// allocation so both cannot race for the same free slot.
    registration_lock: Mutex<()>,
    /// Serializes read-modify-write cycles on the ledger so a concurrent
    /// allocation cannot drop another's entry.
    ledger_lock: Mutex<()>,
    loop_started: AtomicBool,
}

impl RenewalState {
    pub(super) fn registration_lock(&self) -> &Mutex<()> {
        &self.registration_lock
    }

    fn ledger_lock(&self) -> &Mutex<()> {
        &self.ledger_lock
    }
}

/// Read the renewal ledger; an absent or undecodable slot is an empty ledger.
///
/// A ledger this build cannot decode is treated as empty rather than failing
/// the pass: the entries are recipes and raw account ids that
/// [`track_targets`] rebuilds on the next allocation or pairing, so refusing to
/// renew anything is strictly worse than starting over.
async fn read_entries(storage: &(impl CoreStorage + ?Sized)) -> Result<Vec<LedgerEntry>, String> {
    let Some(blob) = storage
        .read_core_storage(CoreStorageKey::StatementRenewalTargets)
        .await
        .map_err(|err| format!("renewal ledger read failed: {}", err.reason))?
    else {
        return Ok(Vec::new());
    };
    match decode_entries(&blob) {
        Ok(entries) => Ok(entries),
        Err(reason) => {
            warn!(%reason, "discarding an undecodable renewal ledger");
            Ok(Vec::new())
        }
    }
}

/// Append `new_targets` to the ledger, preserving order and skipping entries
/// already present.
async fn track_targets(
    storage: &(impl CoreStorage + ?Sized),
    ledger_lock: &Mutex<()>,
    owner: [u8; 32],
    new_targets: Vec<StatementRenewalTarget>,
) -> Result<(), String> {
    let _guard = ledger_lock.lock().await;
    let mut entries = read_entries(storage).await?;
    let mut changed = false;
    for target in new_targets {
        let entry = LedgerEntry::new(target, owner);
        if !entries.contains(&entry) {
            entries.push(entry);
            changed = true;
        }
    }
    if !changed {
        return Ok(());
    }
    write_entries(storage, &entries).await
}

async fn write_entries(
    storage: &(impl CoreStorage + ?Sized),
    entries: &[LedgerEntry],
) -> Result<(), String> {
    storage
        .write_core_storage(CoreStorageKey::StatementRenewalTargets, entries.encode())
        .await
        .map_err(|err| format!("renewal ledger write failed: {}", err.reason))
}

fn decode_entries(blob: &[u8]) -> Result<Vec<LedgerEntry>, String> {
    let mut input = blob;
    let entries = Vec::<LedgerEntry>::decode(&mut input)
        .map_err(|err| format!("invalid persisted renewal targets: {err}"))?;
    if !input.is_empty() {
        return Err("invalid persisted renewal targets: trailing bytes".to_string());
    }
    Ok(entries)
}

/// Resolve a ledger entry into a concrete account for this session's entropy.
fn resolve_target(
    entropy: &[u8],
    target: &StatementRenewalTarget,
) -> Result<ResolvedRenewalTarget, String> {
    match target {
        StatementRenewalTarget::ProductStatementAllowance { product_id } => {
            let pair = derive_sr25519_hard_path(
                entropy,
                &["allowance", "statement-store", product_id.as_str()],
            )
            .map_err(|err| err.to_string())?;
            Ok(ResolvedRenewalTarget {
                label: format!("product:{product_id}"),
                account_id: pair.public.to_bytes(),
            })
        }
        StatementRenewalTarget::WalletSso => {
            let pair = derive_sr25519_hard_path(entropy, &["wallet", "sso"])
                .map_err(|err| err.to_string())?;
            Ok(ResolvedRenewalTarget {
                label: "wallet-sso".to_string(),
                account_id: pair.public.to_bytes(),
            })
        }
        StatementRenewalTarget::Account { account_id, label } => Ok(ResolvedRenewalTarget {
            label: label.clone(),
            account_id: *account_id,
        }),
    }
}

/// Record `targets` in the ledger under the active identity.
pub(super) async fn track(
    signing_host: &SigningHost,
    targets: Vec<StatementRenewalTarget>,
) -> Result<(), String> {
    let entropy = signing_host.root_entropy().map_err(|err| err.to_string())?;
    track_targets(
        signing_host.platform.as_ref(),
        signing_host.renewal.ledger_lock(),
        owner_key(&entropy)?,
        targets,
    )
    .await
}

/// Resolve every ledger target under `entropy`, skipping any that cannot be
/// resolved.
///
/// A target is skipped rather than failing the pass: one unusable entry must
/// not stop every other target from being renewed.
fn resolve_targets(
    entropy: &[u8],
    targets: &[StatementRenewalTarget],
) -> Vec<ResolvedRenewalTarget> {
    targets
        .iter()
        .filter_map(|target| match resolve_target(entropy, target) {
            Ok(resolved) => Some(resolved),
            Err(reason) => {
                warn!(?target, %reason, "skipping an unresolvable renewal target");
                None
            }
        })
        .collect()
}

/// One renewal pass: resolve the ledger against the active session and renew
/// every target for the current period.
pub(super) async fn renew_now(
    services: &Arc<RuntimeServices>,
    signing_host: &SigningHost,
) -> Result<StatementRenewalReport, String> {
    let entropy = signing_host.root_entropy().map_err(|err| err.to_string())?;
    let period = statement_allowance::slot::current_period(
        current_unix_secs().map_err(|err| err.to_string())?,
    );
    let owner = owner_key(&entropy)?;
    let storage = signing_host.platform.as_ref();
    let entries = read_entries(storage).await?;
    // Entries promised by a different identity are dropped rather than renewed:
    // they would consume this identity's slots for an account it never promised.
    let (owned, foreign): (Vec<_>, Vec<_>) = entries
        .into_iter()
        .partition(|entry| entry.is_owned_by(owner));
    if !foreign.is_empty() {
        warn!(
            dropped = foreign.len(),
            "pruning renewal targets promised by a previous identity"
        );
        let _guard = signing_host.renewal.ledger_lock().lock().await;
        write_entries(storage, &owned).await?;
    }
    let targets: Vec<StatementRenewalTarget> =
        owned.into_iter().map(|entry| entry.target).collect();
    let resolved = resolve_targets(&entropy, &targets);
    if resolved.is_empty() {
        return Ok(StatementRenewalReport {
            period,
            outcomes: Vec::new(),
            slots_exhausted: false,
        });
    }

    let bandersnatch = derive_lite_person_ring_vrf_entropy(&entropy);
    let rpc = statement_allowance::rpc::RpcClient::new(
        services
            .statement_store
            .client("statement-allowance renewal")
            .await
            .map_err(|err| err.to_string())?,
    );
    let metadata = fetch_metadata(&rpc).await.map_err(|err| err.to_string())?;
    let chain_state = fetch_chain_state(&rpc)
        .await
        .map_err(|err| err.to_string())?;
    let current = statement_allowance::ring::read_current_ring_index(&rpc)
        .await
        .map_err(|err| err.to_string())?;
    let ring = find_including_ring(&rpc, &metadata, bandersnatch, current)
        .await
        .map_err(|err| err.to_string())?
        .ok_or_else(|| {
            "signing account is not a LitePeople ring member; cannot renew statement-store allowances"
                .to_string()
        })?;
    let context = RenewalChainContext {
        rpc: &rpc,
        metadata: &metadata,
        chain_state: &chain_state,
        ring: &ring,
    };
    Ok(renew_targets(
        &context,
        bandersnatch,
        period,
        &resolved,
        signing_host.renewal.registration_lock(),
    )
    .await)
}

/// Spawn the periodic renewal loop; repeated calls are no-ops. The loop holds
/// only weak references, so it exits when the owning runtime is dropped.
pub(super) fn start_renewal_loop(services: &Arc<RuntimeServices>, signing_host: &Arc<SigningHost>) {
    if signing_host
        .renewal
        .loop_started
        .swap(true, Ordering::SeqCst)
    {
        return;
    }
    let weak_services = Arc::downgrade(services);
    let weak_host = Arc::downgrade(signing_host);
    let spawner = services.spawner.clone();
    spawner(Box::pin(async move {
        loop {
            {
                let (Some(services), Some(signing_host)) =
                    (weak_services.upgrade(), weak_host.upgrade())
                else {
                    return;
                };
                run_tick(&services, &signing_host).await;
            }
            let delay = match current_unix_secs() {
                Ok(now) => next_tick_delay(now),
                Err(_) => CLOCK_FAILURE_TICK_DELAY,
            };
            futures_timer::Delay::new(delay).await;
        }
    }));
}

async fn run_tick(services: &Arc<RuntimeServices>, signing_host: &SigningHost) {
    if signing_host.root_entropy().is_err() {
        debug!("skipping statement-store renewal tick; no active session");
        return;
    }
    match renew_now(services, signing_host).await {
        Ok(report) if report.slots_exhausted => {
            warn!(
                period = report.period,
                "statement-store renewal hit slot exhaustion"
            );
        }
        Ok(report) => {
            info!(
                period = report.period,
                targets = report.outcomes.len(),
                "statement-store renewal pass complete"
            );
        }
        Err(reason) => warn!(%reason, "statement-store renewal tick failed"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;
    use std::sync::Mutex;

    use truapi::latest::GenericError;

    #[derive(Default)]
    struct MemStorage {
        inner: Mutex<HashMap<Vec<u8>, Vec<u8>>>,
    }

    #[truapi_platform::async_trait]
    impl CoreStorage for MemStorage {
        async fn read_core_storage(
            &self,
            key: CoreStorageKey,
        ) -> Result<Option<Vec<u8>>, GenericError> {
            Ok(self
                .inner
                .lock()
                .expect("storage mutex poisoned")
                .get(&key.encode())
                .cloned())
        }

        async fn write_core_storage(
            &self,
            key: CoreStorageKey,
            value: Vec<u8>,
        ) -> Result<(), GenericError> {
            self.inner
                .lock()
                .expect("storage mutex poisoned")
                .insert(key.encode(), value);
            Ok(())
        }

        async fn clear_core_storage(&self, key: CoreStorageKey) -> Result<(), GenericError> {
            self.inner
                .lock()
                .expect("storage mutex poisoned")
                .remove(&key.encode());
            Ok(())
        }
    }

    /// Root public key standing in for the active identity.
    const OWNER: [u8; 32] = [1; 32];
    /// A different identity's root public key.
    const OTHER_OWNER: [u8; 32] = [2; 32];

    /// Yield once, so a concurrently polled task can run.
    async fn yield_once() {
        let mut yielded = false;
        futures::future::poll_fn(move |cx| {
            if yielded {
                core::task::Poll::Ready(())
            } else {
                yielded = true;
                cx.waker().wake_by_ref();
                core::task::Poll::Pending
            }
        })
        .await
    }

    /// Storage that yields *after* serving a read, so a second reader observes
    /// the same value before the first writes its update back. Without
    /// something serializing the cycle, one update is lost.
    #[derive(Default)]
    struct YieldingStorage(MemStorage);

    #[truapi_platform::async_trait]
    impl CoreStorage for YieldingStorage {
        async fn read_core_storage(
            &self,
            key: CoreStorageKey,
        ) -> Result<Option<Vec<u8>>, GenericError> {
            let value = self.0.read_core_storage(key).await;
            yield_once().await;
            value
        }

        async fn write_core_storage(
            &self,
            key: CoreStorageKey,
            value: Vec<u8>,
        ) -> Result<(), GenericError> {
            self.0.write_core_storage(key, value).await
        }

        async fn clear_core_storage(&self, key: CoreStorageKey) -> Result<(), GenericError> {
            self.0.clear_core_storage(key).await
        }
    }

    #[test]
    fn concurrent_tracks_do_not_drop_an_entry() {
        let storage = YieldingStorage::default();
        let ledger_lock = lock();

        futures::executor::block_on(async {
            let (first, second) = futures::join!(
                track_targets(&storage, &ledger_lock, OWNER, vec![product("a.dot")]),
                track_targets(&storage, &ledger_lock, OWNER, vec![product("b.dot")]),
            );
            first.unwrap();
            second.unwrap();

            let mut targets = read_targets(&storage, OWNER).await.unwrap();
            targets.sort_by_key(|target| format!("{target:?}"));
            assert_eq!(targets, vec![product("a.dot"), product("b.dot")]);
        });
    }

    #[test]
    fn an_unresolvable_target_is_skipped_not_fatal() {
        // An all-digit product id past `u64::MAX` fails junction derivation with
        // `NumericJunctionOutOfRange`.
        let unresolvable = product(&"9".repeat(25));
        let entropy = [7u8; 32];

        assert!(resolve_target(&entropy, &unresolvable).is_err());
        let targets = [unresolvable, product("a.dot")];

        // Resolving strictly loses the healthy target with the broken one.
        assert!(
            targets
                .iter()
                .map(|target| resolve_target(&entropy, target))
                .collect::<Result<Vec<_>, _>>()
                .is_err()
        );

        let resolved = resolve_targets(&entropy, &targets);
        assert_eq!(resolved.len(), 1);
        assert_eq!(resolved[0].label, "product:a.dot");
    }

    /// A fresh ledger lock; each test drives one ledger in isolation.
    fn lock() -> futures::lock::Mutex<()> {
        futures::lock::Mutex::new(())
    }

    /// The targets in the ledger visible to the identity rooted at `owner`.
    async fn read_targets(
        storage: &(impl CoreStorage + ?Sized),
        owner: [u8; 32],
    ) -> Result<Vec<StatementRenewalTarget>, String> {
        Ok(read_entries(storage)
            .await?
            .into_iter()
            .filter(|entry| entry.is_owned_by(owner))
            .map(|entry| entry.target)
            .collect())
    }

    fn product(product_id: &str) -> StatementRenewalTarget {
        StatementRenewalTarget::ProductStatementAllowance {
            product_id: product_id.to_string(),
        }
    }

    #[test]
    fn ledger_round_trips_dedupes_and_preserves_order() {
        let storage = MemStorage::default();

        futures::executor::block_on(async {
            track_targets(
                &storage,
                &lock(),
                OWNER,
                vec![StatementRenewalTarget::WalletSso, product("a.dot")],
            )
            .await
            .unwrap();
            track_targets(
                &storage,
                &lock(),
                OWNER,
                vec![
                    product("a.dot"),
                    StatementRenewalTarget::Account {
                        account_id: [9; 32],
                        label: "device".to_string(),
                    },
                ],
            )
            .await
            .unwrap();

            assert_eq!(
                read_targets(&storage, OWNER).await.unwrap(),
                vec![
                    StatementRenewalTarget::WalletSso,
                    product("a.dot"),
                    StatementRenewalTarget::Account {
                        account_id: [9; 32],
                        label: "device".to_string(),
                    },
                ]
            );
        });
    }

    #[test]
    fn ledger_rejects_trailing_bytes() {
        let mut blob = vec![LedgerEntry::new(product("a.dot"), OWNER)].encode();
        blob.push(0xff);
        assert!(decode_entries(&blob).is_err());
    }

    #[test]
    fn an_undecodable_ledger_reads_as_empty() {
        let storage = MemStorage::default();

        futures::executor::block_on(async {
            storage
                .write_core_storage(
                    CoreStorageKey::StatementRenewalTargets,
                    vec![0xff, 0xff, 0xff],
                )
                .await
                .unwrap();

            assert_eq!(read_targets(&storage, OWNER).await.unwrap(), Vec::new());
        });
    }

    #[test]
    fn tracking_over_an_undecodable_ledger_starts_a_fresh_one() {
        let storage = MemStorage::default();

        futures::executor::block_on(async {
            storage
                .write_core_storage(CoreStorageKey::StatementRenewalTargets, vec![0xff; 3])
                .await
                .unwrap();
            track_targets(&storage, &lock(), OWNER, vec![product("a.dot")])
                .await
                .unwrap();

            assert_eq!(
                read_targets(&storage, OWNER).await.unwrap(),
                vec![product("a.dot")]
            );
        });
    }

    #[test]
    fn product_target_resolves_to_allocation_derivation() {
        let entropy = [7u8; 32];
        let expected =
            derive_sr25519_hard_path(&entropy, &["allowance", "statement-store", "a.dot"])
                .unwrap()
                .public
                .to_bytes();

        let resolved = resolve_target(&entropy, &product("a.dot")).unwrap();
        assert_eq!(
            resolved,
            ResolvedRenewalTarget {
                label: "product:a.dot".to_string(),
                account_id: expected,
            }
        );
    }

    #[test]
    fn wallet_sso_target_resolves_to_wallet_sso_derivation() {
        let entropy = [7u8; 32];
        let expected = derive_sr25519_hard_path(&entropy, &["wallet", "sso"])
            .unwrap()
            .public
            .to_bytes();

        let resolved = resolve_target(&entropy, &StatementRenewalTarget::WalletSso).unwrap();
        assert_eq!(
            resolved,
            ResolvedRenewalTarget {
                label: "wallet-sso".to_string(),
                account_id: expected,
            }
        );
    }

    #[test]
    fn a_raw_account_is_hidden_from_another_identity() {
        let storage = MemStorage::default();
        let device = StatementRenewalTarget::Account {
            account_id: [9; 32],
            label: "device".to_string(),
        };

        futures::executor::block_on(async {
            track_targets(
                &storage,
                &lock(),
                OWNER,
                vec![device.clone(), product("a.dot")],
            )
            .await
            .unwrap();

            // The recipe resolves under any identity; the raw account does not.
            assert_eq!(
                read_targets(&storage, OWNER).await.unwrap(),
                vec![device, product("a.dot")]
            );
            assert_eq!(
                read_targets(&storage, OTHER_OWNER).await.unwrap(),
                vec![product("a.dot")]
            );
        });
    }

    #[test]
    fn the_same_raw_account_can_be_promised_by_two_identities() {
        let storage = MemStorage::default();
        let device = StatementRenewalTarget::Account {
            account_id: [9; 32],
            label: "device".to_string(),
        };

        futures::executor::block_on(async {
            track_targets(&storage, &lock(), OWNER, vec![device.clone()])
                .await
                .unwrap();
            track_targets(&storage, &lock(), OTHER_OWNER, vec![device.clone()])
                .await
                .unwrap();

            // Distinct owners, so each identity renews it for itself.
            assert_eq!(
                read_targets(&storage, OWNER).await.unwrap(),
                vec![device.clone()]
            );
            assert_eq!(
                read_targets(&storage, OTHER_OWNER).await.unwrap(),
                vec![device]
            );
        });
    }

    #[test]
    fn owner_key_follows_the_root_entropy() {
        assert_ne!(
            owner_key(&[7u8; 32]).unwrap(),
            owner_key(&[8u8; 32]).unwrap()
        );
    }
}
