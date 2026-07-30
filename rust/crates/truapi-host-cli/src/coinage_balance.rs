//! Wallet-local Coinage inventory and chain reconciliation for `/balance`.

use std::collections::{BTreeMap, HashMap};
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result, bail};
use async_trait::async_trait;
use chrono::{DateTime, SecondsFormat, Utc};
use futures_util::future::try_join_all;
use parity_scale_codec::Decode;
use rayon::prelude::*;
use scale_decode::DecodeAsType;
use serde::{Deserialize, Serialize};
use sp_crypto_hashing::{blake2_128, twox_128};
use subxt::client::{OnlineClient, OnlineClientAtBlock};
use subxt::config::substrate::SubstrateConfig;
use subxt::dynamic;
use subxt_rpcs::client::{RpcClient, rpc_params};
use truapi_server::host_logic::coinage::{derive_coin_public_key, derive_voucher_keys};

const SCAN_STATE_FILE: &str = "coinage-balance-scan.json";
const SCAN_STATE_VERSION: u32 = 2;
const BATCH_SIZE: u32 = 500;
const EMPTY_BATCH_LIMIT: usize = 4;
const RECYCLE_AT_AGE: u16 = 14;
const MINIMUM_FULL_PRIVACY_RING_SIZE: u32 = 10;

/// Human-readable values rendered by `/balance`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CashBalance {
    pub total: String,
    pub on_hold: Option<String>,
}

/// Balance plus the first voucher derivation index not known locally or
/// observed on chain.
pub struct CashDiscovery {
    pub balance: CashBalance,
    pub next_voucher_index: u32,
    details: CashDetails,
}

impl CashDiscovery {
    /// Render local inventory and latest chain detail for `/balance --verbose`.
    pub fn verbose_lines(&self) -> Vec<String> {
        let mut lines = vec![format!("Coins ({})", self.details.coins.len())];
        if self.details.coins.is_empty() {
            lines.push("  none".to_string());
        } else {
            lines.extend(
                self.details
                    .coins
                    .iter()
                    .map(|detail| format!("  {detail}")),
            );
        }
        lines.push(format!("Vouchers ({})", self.details.vouchers.len()));
        if self.details.vouchers.is_empty() {
            lines.push("  none".to_string());
        } else {
            lines.extend(
                self.details
                    .vouchers
                    .iter()
                    .map(|detail| format!("  {detail}")),
            );
        }
        lines.push(
            "Allocation and ready-at times are shown for locally allocated vouchers; chain-recovered vouchers have no historical timestamps."
                .to_string(),
        );
        lines
    }
}

/// Reconcile and read the active wallet's Coinage balance at one finalized
/// chain snapshot.
pub async fn read(
    people_ws: &str,
    root_entropy: &[u8],
    session_path: Option<&Path>,
) -> Result<CashBalance> {
    Ok(
        discover_with_mode(people_ws, root_entropy, session_path, false, false)
            .await?
            .balance,
    )
}

/// Reconcile the active wallet's balance and next safe voucher derivation index
/// at one finalized chain snapshot.
pub async fn discover(
    people_ws: &str,
    root_entropy: &[u8],
    session_path: Option<&Path>,
) -> Result<CashDiscovery> {
    discover_with_mode(people_ws, root_entropy, session_path, false, false).await
}

/// Reconcile the active wallet's balance and enrich every included voucher
/// with its finalized recycler status for verbose rendering.
pub async fn inspect(
    people_ws: &str,
    root_entropy: &[u8],
    session_path: Option<&Path>,
) -> Result<CashDiscovery> {
    discover_with_mode(people_ws, root_entropy, session_path, true, false).await
}

/// Scan the next unexplored private-balance range, persist newly recovered
/// items, and return the reconciled balance. Repeated calls advance the
/// recovery horizon like the mobile wallet's manual Update action.
pub async fn recover(
    people_ws: &str,
    root_entropy: &[u8],
    session_path: Option<&Path>,
    verbose: bool,
) -> Result<CashDiscovery> {
    discover_with_mode(people_ws, root_entropy, session_path, verbose, true).await
}

async fn discover_with_mode(
    people_ws: &str,
    root_entropy: &[u8],
    session_path: Option<&Path>,
    verbose: bool,
    recover: bool,
) -> Result<CashDiscovery> {
    let query = ChainSnapshot::connect(people_ws).await?;
    let state_path = session_path.map(|path| path.join(SCAN_STATE_FILE));
    let mut state = state_path
        .as_deref()
        .map(load_scan_state)
        .transpose()?
        .unwrap_or_default();
    let wallet_id = wallet_id(root_entropy)?;
    let discovery = read_with_query_mode(
        &query,
        root_entropy,
        state.wallet_mut(&wallet_id),
        verbose,
        recover,
    )
    .await?;
    if let Some(path) = state_path {
        save_scan_state(&path, &state)?;
    }
    Ok(discovery)
}

/// Add successfully allocated vouchers to the profile's wallet-local
/// inventory. Chain reconciliation on later balance reads updates their remote
/// state without dropping records that are temporarily undiscoverable.
pub fn record_allocated_vouchers(
    session_path: Option<&Path>,
    root_entropy: &[u8],
    vouchers: &[(u32, i8, u64, u64)],
) -> Result<()> {
    let Some(session_path) = session_path else {
        return Ok(());
    };
    if vouchers.is_empty() {
        return Ok(());
    }

    let path = session_path.join(SCAN_STATE_FILE);
    let mut state = load_scan_state(&path)?;
    let wallet_id = wallet_id(root_entropy)?;
    let wallet = state.wallet_mut(&wallet_id);
    for &(index, exponent, allocated_at_unix_ms, ready_at_unix_ms) in vouchers {
        wallet.vouchers.insert(
            index,
            StoredVoucher::allocated(exponent, allocated_at_unix_ms, ready_at_unix_ms),
        );
        wallet.highest_voucher_index = Some(
            wallet
                .highest_voucher_index
                .map_or(index, |highest| highest.max(index)),
        );
    }
    save_scan_state(&path, &state)
}

fn wallet_id(root_entropy: &[u8]) -> Result<String> {
    let first = derive_voucher_keys(root_entropy, 0).context("derive Coinage wallet id")?;
    Ok(hex::encode(first.member))
}

#[derive(Debug, Clone, Copy)]
struct Denomination {
    unit: u128,
    precision: u8,
    minimum_exponent: i8,
    maximum_exponent: i8,
}

impl Denomination {
    fn value(self, exponent: i8) -> Result<u128> {
        if exponent < self.minimum_exponent || exponent > self.maximum_exponent {
            bail!(
                "Coinage denomination exponent {exponent} is outside runtime range {}..={}",
                self.minimum_exponent,
                self.maximum_exponent
            );
        }
        let shift = u32::from(exponent.unsigned_abs());
        if exponent >= 0 {
            self.unit
                .checked_shl(shift)
                .with_context(|| format!("Coinage denomination 2^{exponent} overflows"))
        } else {
            Ok(self.unit.checked_shr(shift).unwrap_or(0))
        }
    }

    fn format(self, planks: u128) -> Result<String> {
        let minor_units = if self.precision >= 2 {
            let divisor = checked_pow10(u32::from(self.precision - 2))?;
            let mut rounded = planks / divisor;
            let remainder = planks % divisor;
            if remainder >= divisor.div_ceil(2) {
                rounded = rounded
                    .checked_add(1)
                    .context("rounded CASH balance overflows")?;
            }
            rounded
        } else {
            planks
                .checked_mul(checked_pow10(u32::from(2 - self.precision))?)
                .context("scaled CASH balance overflows")?
        };
        Ok(format!("{}.{:02}", minor_units / 100, minor_units % 100))
    }
}

fn checked_pow10(exponent: u32) -> Result<u128> {
    10u128
        .checked_pow(exponent)
        .with_context(|| format!("asset precision 10^{exponent} overflows"))
}

#[derive(Debug, Clone, Copy)]
struct CoinState {
    exponent: i8,
    age: u16,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
struct VoucherState {
    exponent: i8,
    on_hold: bool,
    counted: bool,
    location: VoucherLocation,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
enum VoucherLocation {
    Unlocated,
    Onboarding,
    Included {
        ring_index: u32,
        ring_position: u32,
        ring_total: Option<u32>,
        ring_included: Option<u32>,
    },
    Suspended,
    Unloaded {
        ring_index: u32,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
struct StoredVoucher {
    #[serde(flatten)]
    state: VoucherState,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    allocated_at_unix_ms: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    ready_at_unix_ms: Option<u64>,
}

impl StoredVoucher {
    fn recovered(state: VoucherState) -> Self {
        Self {
            state,
            allocated_at_unix_ms: None,
            ready_at_unix_ms: None,
        }
    }

    fn allocated(exponent: i8, allocated_at_unix_ms: u64, ready_at_unix_ms: u64) -> Self {
        Self {
            state: VoucherState {
                exponent,
                on_hold: true,
                counted: true,
                location: VoucherLocation::Unlocated,
            },
            allocated_at_unix_ms: Some(allocated_at_unix_ms),
            ready_at_unix_ms: Some(ready_at_unix_ms),
        }
    }

    fn observe(&mut self, state: VoucherState) {
        self.state = state;
    }
}

#[derive(Debug, Default)]
struct CashDetails {
    coins: Vec<String>,
    vouchers: Vec<String>,
}

#[derive(Debug, Default, Clone, PartialEq, Eq, Serialize, Deserialize)]
struct ScanState {
    #[serde(default = "scan_state_version")]
    version: u32,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    wallets: BTreeMap<String, WalletScanState>,
    // Version 1 stored one unscoped high-water mark. These fields are read only
    // for migration and are bound to the first signer that opens the profile.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    highest_coin_index: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    highest_voucher_index: Option<u32>,
}

#[derive(Debug, Default, Clone, PartialEq, Eq, Serialize, Deserialize)]
struct WalletScanState {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    highest_coin_index: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    highest_voucher_index: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    coin_scan_horizon: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    voucher_scan_horizon: Option<u32>,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    vouchers: BTreeMap<u32, StoredVoucher>,
}

const fn scan_state_version() -> u32 {
    SCAN_STATE_VERSION
}

impl ScanState {
    fn wallet_mut(&mut self, wallet_id: &str) -> &mut WalletScanState {
        if self.version == 1 && self.wallets.is_empty() {
            self.wallets.insert(
                wallet_id.to_string(),
                WalletScanState {
                    highest_coin_index: self.highest_coin_index.take(),
                    highest_voucher_index: self.highest_voucher_index.take(),
                    coin_scan_horizon: None,
                    voucher_scan_horizon: None,
                    vouchers: BTreeMap::new(),
                },
            );
        }
        self.version = SCAN_STATE_VERSION;
        self.wallets.entry(wallet_id.to_string()).or_default()
    }
}

#[async_trait]
trait CoinageQuery: Send + Sync {
    fn denomination(&self) -> Denomination;

    async fn coins(&self, root_entropy: &[u8], indices: &[u32]) -> Result<Vec<Option<CoinState>>>;

    async fn vouchers(
        &self,
        root_entropy: &[u8],
        indices: &[u32],
        known: &BTreeMap<u32, StoredVoucher>,
    ) -> Result<Vec<Option<VoucherState>>>;

    async fn populate_voucher_details(&self, _vouchers: &mut [(u32, VoucherState)]) -> Result<()> {
        Ok(())
    }
}

struct Scanned<T> {
    items: Vec<(u32, T)>,
    highest_found: Option<u32>,
    horizon: Option<u32>,
}

async fn read_with_query_mode<Q: CoinageQuery>(
    query: &Q,
    root_entropy: &[u8],
    state: &mut WalletScanState,
    verbose: bool,
    recover: bool,
) -> Result<CashDiscovery> {
    let (coins, scanned_vouchers) = tokio::try_join!(
        scan_coins(
            query,
            root_entropy,
            state.highest_coin_index,
            state.coin_scan_horizon,
            recover,
        ),
        scan_vouchers(
            query,
            root_entropy,
            state.highest_voucher_index,
            state.voucher_scan_horizon,
            &state.vouchers,
            recover,
        ),
    )?;
    state.highest_coin_index = coins.highest_found;
    state.highest_voucher_index = scanned_vouchers.highest_found;
    state.coin_scan_horizon = max_horizon(state.coin_scan_horizon, coins.horizon);
    state.voucher_scan_horizon = max_horizon(state.voucher_scan_horizon, scanned_vouchers.horizon);
    reconcile_vouchers(&mut state.vouchers, scanned_vouchers.items);
    if let Some(highest) = state.vouchers.keys().next_back().copied() {
        state.highest_voucher_index = Some(
            state
                .highest_voucher_index
                .map_or(highest, |known| known.max(highest)),
        );
    }
    if verbose {
        let mut voucher_states = state
            .vouchers
            .iter()
            .map(|(&index, voucher)| (index, voucher.state))
            .collect::<Vec<_>>();
        query.populate_voucher_details(&mut voucher_states).await?;
        reconcile_vouchers(&mut state.vouchers, voucher_states);
    }

    let denomination = query.denomination();
    let vouchers = state
        .vouchers
        .iter()
        .map(|(&index, voucher)| (index, *voucher))
        .collect::<Vec<_>>();
    let details = cash_details(denomination, &coins.items, &vouchers)?;
    let mut total = 0u128;
    let mut on_hold = 0u128;
    for (_, coin) in coins.items {
        let value = denomination.value(coin.exponent)?;
        total = total.checked_add(value).context("CASH balance overflows")?;
        if coin.age >= RECYCLE_AT_AGE {
            on_hold = on_hold
                .checked_add(value)
                .context("CASH on-hold balance overflows")?;
        }
    }
    for (_, voucher) in vouchers
        .into_iter()
        .filter(|(_, voucher)| voucher.state.counted)
    {
        let value = denomination.value(voucher.state.exponent)?;
        total = total.checked_add(value).context("CASH balance overflows")?;
        if voucher.state.on_hold {
            on_hold = on_hold
                .checked_add(value)
                .context("CASH on-hold balance overflows")?;
        }
    }

    let next_voucher_index = state.highest_voucher_index.map_or(Ok(0), |index| {
        index
            .checked_add(1)
            .context("Coinage voucher derivation indices are exhausted")
    })?;
    Ok(CashDiscovery {
        balance: CashBalance {
            total: denomination.format(total)?,
            on_hold: (on_hold > 0)
                .then(|| denomination.format(on_hold))
                .transpose()?,
        },
        next_voucher_index,
        details,
    })
}

fn reconcile_vouchers(
    inventory: &mut BTreeMap<u32, StoredVoucher>,
    observations: Vec<(u32, VoucherState)>,
) {
    for (index, observation) in observations {
        inventory
            .entry(index)
            .and_modify(|voucher| voucher.observe(observation))
            .or_insert_with(|| StoredVoucher::recovered(observation));
    }
}

fn max_horizon(current: Option<u32>, observed: Option<u32>) -> Option<u32> {
    match (current, observed) {
        (Some(current), Some(observed)) => Some(current.max(observed)),
        (current, observed) => current.or(observed),
    }
}

fn voucher_timing(voucher: &StoredVoucher) -> Result<String> {
    let (Some(allocated), Some(ready)) = (voucher.allocated_at_unix_ms, voucher.ready_at_unix_ms)
    else {
        return Ok(String::new());
    };
    Ok(format!(
        " · allocated {} · ready {}",
        format_unix_ms(allocated)?,
        format_unix_ms(ready)?
    ))
}

fn format_unix_ms(timestamp: u64) -> Result<String> {
    let timestamp = i64::try_from(timestamp).context("voucher timestamp is out of range")?;
    let date = DateTime::<Utc>::from_timestamp_millis(timestamp)
        .context("voucher timestamp is out of range")?;
    let precision = if timestamp % 1_000 == 0 {
        SecondsFormat::Secs
    } else {
        SecondsFormat::Millis
    };
    Ok(date.to_rfc3339_opts(precision, true))
}

fn cash_details(
    denomination: Denomination,
    coins: &[(u32, CoinState)],
    vouchers: &[(u32, StoredVoucher)],
) -> Result<CashDetails> {
    let now = current_unix_ms()?;
    let coins = coins
        .iter()
        .map(|(index, coin)| {
            let amount = denomination.format(denomination.value(coin.exponent)?)?;
            let state = if coin.age >= RECYCLE_AT_AGE {
                "on hold"
            } else {
                "available"
            };
            Ok(format!(
                "#{index} · 2^{} · {amount} CASH · {state} · age {}",
                coin.exponent, coin.age
            ))
        })
        .collect::<Result<Vec<_>>>()?;
    let vouchers = vouchers
        .iter()
        .map(|(index, voucher)| {
            let voucher_state = voucher.state;
            let amount = denomination.format(denomination.value(voucher_state.exponent)?)?;
            let time_ready = voucher
                .ready_at_unix_ms
                .is_none_or(|ready_at| ready_at <= now);
            let (state, privacy, ring) = voucher_detail(voucher_state.location, time_ready);
            let excluded = (!voucher_state.counted).then_some(" · excluded from balance");
            let timing = voucher_timing(voucher)?;
            Ok(format!(
                "#{index} · 2^{} · {amount} CASH · {state} · {privacy}{}{}{timing}",
                voucher_state.exponent,
                ring.map_or_else(String::new, |ring| format!(" · {ring}")),
                excluded.unwrap_or_default(),
            ))
        })
        .collect::<Result<Vec<_>>>()?;
    Ok(CashDetails { coins, vouchers })
}

fn voucher_detail(
    location: VoucherLocation,
    time_ready: bool,
) -> (&'static str, &'static str, Option<String>) {
    match location {
        VoucherLocation::Unlocated => ("unlocated", "degraded", None),
        VoucherLocation::Onboarding => ("pending", "degraded", None),
        VoucherLocation::Suspended => ("suspended", "degraded", None),
        VoucherLocation::Unloaded { ring_index } => (
            "unloaded",
            "privacy n/a",
            Some(format!("ring {ring_index}")),
        ),
        VoucherLocation::Included {
            ring_index,
            ring_position,
            ring_total,
            ring_included,
        } => {
            let state = if ring_included.is_none_or(|included| included > ring_position) {
                "in recycler"
            } else {
                "pending"
            };
            let privacy = if time_ready
                && ring_included.is_some_and(|included| included >= MINIMUM_FULL_PRIVACY_RING_SIZE)
            {
                "full"
            } else {
                "degraded"
            };
            let ring = match (ring_included, ring_total) {
                (Some(included), Some(total)) => {
                    format!("ring {ring_index} ({included}/{total} included)")
                }
                _ => format!("ring {ring_index}"),
            };
            (state, privacy, Some(ring))
        }
    }
}

fn current_unix_ms() -> Result<u64> {
    let milliseconds = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .context("system clock is before the Unix epoch")?
        .as_millis();
    u64::try_from(milliseconds).context("system time exceeds u64 milliseconds")
}

async fn scan_coins<Q: CoinageQuery>(
    query: &Q,
    root_entropy: &[u8],
    known_highest: Option<u32>,
    previous_horizon: Option<u32>,
    recover: bool,
) -> Result<Scanned<CoinState>> {
    let mut scanned = Scanned {
        items: Vec::new(),
        highest_found: known_highest,
        horizon: None,
    };
    if let Some(highest) = known_highest {
        let mut start = 0u32;
        loop {
            let end = start.saturating_add(BATCH_SIZE - 1).min(highest);
            let indices = inclusive_indices(start, end);
            let batch = query.coins(root_entropy, &indices).await?;
            absorb_batch(&indices, batch, &mut scanned)?;
            scanned.horizon = max_horizon(scanned.horizon, Some(end));
            if end == highest {
                break;
            }
            start = end + 1;
        }
    }

    let Some(mut start) = scan_extension_start(known_highest, previous_horizon, recover) else {
        return Ok(scanned);
    };
    let mut empty_batches = 0;
    while empty_batches < EMPTY_BATCH_LIMIT {
        let end = start.saturating_add(BATCH_SIZE - 1);
        let indices = inclusive_indices(start, end);
        let batch = query.coins(root_entropy, &indices).await?;
        if absorb_batch(&indices, batch, &mut scanned)? {
            empty_batches = 0;
        } else {
            empty_batches += 1;
        }
        scanned.horizon = max_horizon(scanned.horizon, Some(end));
        let Some(next) = end.checked_add(1) else {
            break;
        };
        start = next;
    }
    Ok(scanned)
}

async fn scan_vouchers<Q: CoinageQuery>(
    query: &Q,
    root_entropy: &[u8],
    known_highest: Option<u32>,
    previous_horizon: Option<u32>,
    known_vouchers: &BTreeMap<u32, StoredVoucher>,
    recover: bool,
) -> Result<Scanned<VoucherState>> {
    let mut scanned = Scanned {
        items: Vec::new(),
        highest_found: known_highest,
        horizon: None,
    };
    if let Some(highest) = known_highest {
        let mut start = 0u32;
        loop {
            let end = start.saturating_add(BATCH_SIZE - 1).min(highest);
            let indices = inclusive_indices(start, end);
            let batch = query
                .vouchers(root_entropy, &indices, known_vouchers)
                .await?;
            absorb_batch(&indices, batch, &mut scanned)?;
            scanned.horizon = max_horizon(scanned.horizon, Some(end));
            if end == highest {
                break;
            }
            start = end + 1;
        }
    }

    let Some(mut start) = scan_extension_start(known_highest, previous_horizon, recover) else {
        return Ok(scanned);
    };
    let mut empty_batches = 0;
    while empty_batches < EMPTY_BATCH_LIMIT {
        let end = start.saturating_add(BATCH_SIZE - 1);
        let indices = inclusive_indices(start, end);
        let batch = query
            .vouchers(root_entropy, &indices, known_vouchers)
            .await?;
        if absorb_batch(&indices, batch, &mut scanned)? {
            empty_batches = 0;
        } else {
            empty_batches += 1;
        }
        scanned.horizon = max_horizon(scanned.horizon, Some(end));
        let Some(next) = end.checked_add(1) else {
            break;
        };
        start = next;
    }
    Ok(scanned)
}

fn scan_extension_start(
    known_highest: Option<u32>,
    previous_horizon: Option<u32>,
    recover: bool,
) -> Option<u32> {
    let after_known = known_highest.map_or(Some(0), |highest| highest.checked_add(1))?;
    if !recover {
        return Some(after_known);
    }
    let Some(previous_horizon) = previous_horizon else {
        return Some(after_known);
    };
    previous_horizon
        .checked_add(1)
        .map(|after_horizon| after_known.max(after_horizon))
}

fn inclusive_indices(start: u32, end: u32) -> Vec<u32> {
    (start..=end).collect()
}

fn absorb_batch<T>(
    indices: &[u32],
    batch: Vec<Option<T>>,
    scanned: &mut Scanned<T>,
) -> Result<bool> {
    if indices.len() != batch.len() {
        bail!(
            "Coinage query returned {} entries for {} indices",
            batch.len(),
            indices.len()
        );
    }
    let mut found = false;
    for (index, item) in indices.iter().copied().zip(batch) {
        if let Some(item) = item {
            found = true;
            scanned.highest_found = Some(
                scanned
                    .highest_found
                    .map_or(index, |highest| highest.max(index)),
            );
            scanned.items.push((index, item));
        }
    }
    Ok(found)
}

#[derive(Decode)]
struct OnChainCoin {
    value: i8,
    age: u16,
}

#[derive(Decode)]
enum RingPosition {
    Onboarding {
        _queue_page: u32,
        _queued_at: u64,
    },
    Included {
        ring_index: u32,
        _ring_page: u32,
        ring_position: u32,
    },
    Suspended,
}

#[derive(Decode)]
struct AssetMetadata {
    _deposit: u128,
    _name: Vec<u8>,
    _symbol: Vec<u8>,
    decimals: u8,
    _is_frozen: bool,
}

#[derive(DecodeAsType)]
struct RingKeysStatus {
    total: u32,
    included: u32,
}

#[derive(Deserialize)]
struct StorageChangeSet {
    changes: Vec<(String, Option<String>)>,
}

struct ChainSnapshot {
    rpc: RpcClient,
    at: OnlineClientAtBlock<SubstrateConfig>,
    block_hash: String,
    denomination: Denomination,
}

impl ChainSnapshot {
    async fn connect(url: &str) -> Result<Self> {
        let rpc = RpcClient::from_insecure_url(url)
            .await
            .with_context(|| format!("connect Coinage RPC {url}"))?;
        let client = OnlineClient::<SubstrateConfig>::from_rpc_client(rpc.clone())
            .await
            .context("initialize Coinage chain client")?;
        let at = client
            .at_current_block()
            .await
            .context("resolve finalized Coinage block")?;
        let block_hash = format!("{:?}", at.block_hash());
        let constants = at.constants();
        let unit = constants
            .entry(dynamic::constant::<u128>("Coinage", "UnderlyingAssetUnit"))
            .context("read Coinage.UnderlyingAssetUnit")?;
        let minimum_exponent = constants
            .entry(dynamic::constant::<i8>("Coinage", "MinimumExponent"))
            .context("read Coinage.MinimumExponent")?;
        let maximum_exponent = constants
            .entry(dynamic::constant::<i8>("Coinage", "MaximumExponent"))
            .context("read Coinage.MaximumExponent")?;

        let underlying_entry = at
            .storage()
            .entry(dynamic::storage::<(), ()>("Coinage", "UnderlyingAssetId"))
            .context("resolve Coinage.UnderlyingAssetId")?;
        let underlying_key = underlying_entry
            .fetch_key(())
            .context("encode Coinage.UnderlyingAssetId key")?;
        let underlying = query_storage_values(&rpc, &block_hash, vec![underlying_key.clone()])
            .await?
            .remove(&underlying_key)
            .context("Coinage underlying asset is not configured")?;
        let metadata_key = asset_metadata_key(&underlying);
        let metadata = query_storage_values(&rpc, &block_hash, vec![metadata_key.clone()])
            .await?
            .remove(&metadata_key)
            .context("Coinage underlying asset has no Assets.Metadata record")?;
        let metadata: AssetMetadata = decode_value(&metadata, "Assets.Metadata")?;

        Ok(Self {
            rpc,
            at,
            block_hash,
            denomination: Denomination {
                unit,
                precision: metadata.decimals,
                minimum_exponent,
                maximum_exponent,
            },
        })
    }

    async fn values(&self, keys: Vec<Vec<u8>>) -> Result<HashMap<Vec<u8>, Vec<u8>>> {
        query_storage_values(&self.rpc, &self.block_hash, keys).await
    }
}

#[async_trait]
impl CoinageQuery for ChainSnapshot {
    fn denomination(&self) -> Denomination {
        self.denomination
    }

    async fn coins(&self, root_entropy: &[u8], indices: &[u32]) -> Result<Vec<Option<CoinState>>> {
        let entry = self
            .at
            .storage()
            .entry(dynamic::storage::<([u8; 32],), ()>(
                "Coinage",
                "CoinsByOwner",
            ))
            .context("resolve Coinage.CoinsByOwner")?;
        let keys = indices
            .par_iter()
            .map(|index| {
                let public = derive_coin_public_key(root_entropy, *index)
                    .with_context(|| format!("derive coin key {index}"))?;
                entry
                    .fetch_key((public,))
                    .with_context(|| format!("encode Coinage coin key {index}"))
            })
            .collect::<Result<Vec<_>>>()?;
        let values = self.values(keys.clone()).await?;
        keys.iter()
            .map(|key| {
                values
                    .get(key)
                    .map(|value| {
                        let coin: OnChainCoin = decode_value(value, "Coinage.CoinsByOwner")?;
                        Ok(CoinState {
                            exponent: coin.value,
                            age: coin.age,
                        })
                    })
                    .transpose()
            })
            .collect()
    }

    async fn vouchers(
        &self,
        root_entropy: &[u8],
        indices: &[u32],
        known: &BTreeMap<u32, StoredVoucher>,
    ) -> Result<Vec<Option<VoucherState>>> {
        let materials = indices
            .par_iter()
            .map(|index| {
                derive_voucher_keys(root_entropy, *index)
                    .with_context(|| format!("derive voucher key {index}"))
            })
            .collect::<Result<Vec<_>>>()?;
        let recycler_entry = self
            .at
            .storage()
            .entry(dynamic::storage::<([u8; 32],), ()>(
                "Coinage",
                "RecyclersCoinToRecycler",
            ))
            .context("resolve Coinage.RecyclersCoinToRecycler")?;
        let recycler_keys = materials
            .iter()
            .map(|material| recycler_entry.fetch_key((material.member,)))
            .collect::<Result<Vec<_>, _>>()
            .context("encode Coinage recycler keys")?;
        let recycler_values = self.values(recycler_keys.clone()).await?;

        let members_entry = self
            .at
            .storage()
            .entry(dynamic::storage::<([u8; 32], [u8; 32]), ()>(
                "Members", "Members",
            ))
            .context("resolve Members.Members")?;
        let mut located = Vec::new();
        for (position, ((material, recycler_key), _index)) in materials
            .iter()
            .zip(&recycler_keys)
            .zip(indices)
            .enumerate()
        {
            let Some(value) = recycler_values.get(recycler_key) else {
                continue;
            };
            let exponent: i8 = decode_value(value, "Coinage.RecyclersCoinToRecycler")?;
            let collection = recycler_collection(exponent);
            let member_key = members_entry
                .fetch_key((collection, material.member))
                .context("encode recycler Members key")?;
            located.push((position, exponent, *material, member_key));
        }

        let member_keys = located
            .iter()
            .map(|(_, _, _, key)| key.clone())
            .collect::<Vec<_>>();
        let member_values = self.values(member_keys).await?;
        let unloaded_entry = self
            .at
            .storage()
            .entry(dynamic::storage::<(i8, u32, [u8; 32]), ()>(
                "Coinage",
                "RecyclersUnloaded",
            ))
            .context("resolve Coinage.RecyclersUnloaded")?;
        let mut output = vec![None; indices.len()];
        let mut included = Vec::new();
        for (position, exponent, material, member_key) in located {
            let Some(value) = member_values.get(&member_key) else {
                continue;
            };
            match decode_value(value, "Members.Members")? {
                RingPosition::Included {
                    ring_index,
                    ring_position,
                    ..
                } => {
                    let unloaded_key = unloaded_entry
                        .fetch_key((exponent, ring_index, material.recycler_alias))
                        .context("encode Coinage unloaded voucher key")?;
                    included.push((position, exponent, ring_index, ring_position, unloaded_key));
                }
                RingPosition::Onboarding { .. } => {
                    output[position] = Some(VoucherState {
                        exponent,
                        on_hold: true,
                        counted: true,
                        location: VoucherLocation::Onboarding,
                    });
                }
                RingPosition::Suspended => {
                    output[position] = Some(VoucherState {
                        exponent,
                        on_hold: true,
                        counted: true,
                        location: VoucherLocation::Suspended,
                    });
                }
            }
        }

        let unloaded_keys = included
            .iter()
            .map(|(_, _, _, _, key)| key.clone())
            .collect::<Vec<_>>();
        let unloaded_values = self.values(unloaded_keys).await?;
        for (position, exponent, ring_index, ring_position, unloaded_key) in included {
            let unloaded = unloaded_values.contains_key(&unloaded_key);
            output[position] = Some(VoucherState {
                exponent,
                on_hold: false,
                counted: !unloaded,
                location: if unloaded {
                    VoucherLocation::Unloaded { ring_index }
                } else {
                    VoucherLocation::Included {
                        ring_index,
                        ring_position,
                        ring_total: None,
                        ring_included: None,
                    }
                },
            });
        }

        // Members may no longer expose an older voucher even though the
        // unload marker remains queryable. A persisted recycler location lets
        // us still reconcile that voucher instead of indefinitely retaining a
        // stale spendable balance.
        let fallback_unloaded = indices
            .iter()
            .enumerate()
            .filter_map(|(position, index)| {
                if output[position].is_some() {
                    return None;
                }
                let stored = known.get(index)?;
                let ring_index = match stored.state.location {
                    VoucherLocation::Included { ring_index, .. }
                    | VoucherLocation::Unloaded { ring_index } => ring_index,
                    VoucherLocation::Unlocated
                    | VoucherLocation::Onboarding
                    | VoucherLocation::Suspended => return None,
                };
                Some(
                    unloaded_entry
                        .fetch_key((
                            stored.state.exponent,
                            ring_index,
                            materials[position].recycler_alias,
                        ))
                        .map(|key| (position, stored.state.exponent, ring_index, key)),
                )
            })
            .collect::<Result<Vec<_>, _>>()
            .context("encode persisted Coinage unloaded voucher keys")?;
        let fallback_values = self
            .values(
                fallback_unloaded
                    .iter()
                    .map(|(_, _, _, key)| key.clone())
                    .collect(),
            )
            .await?;
        for (position, exponent, ring_index, key) in fallback_unloaded {
            if fallback_values.contains_key(&key) {
                output[position] = Some(VoucherState {
                    exponent,
                    on_hold: false,
                    counted: false,
                    location: VoucherLocation::Unloaded { ring_index },
                });
            }
        }
        Ok(output)
    }

    async fn populate_voucher_details(&self, vouchers: &mut [(u32, VoucherState)]) -> Result<()> {
        let storage = self.at.storage();
        let mut positions_by_ring = HashMap::<(i8, u32), Vec<usize>>::new();
        for (position, (_, voucher)) in vouchers.iter().enumerate() {
            let VoucherLocation::Included { ring_index, .. } = voucher.location else {
                continue;
            };
            positions_by_ring
                .entry((voucher.exponent, ring_index))
                .or_default()
                .push(position);
        }
        let statuses = try_join_all(positions_by_ring.into_iter().map(
            |((exponent, ring_index), positions)| {
                let storage = &storage;
                async move {
                    let collection = recycler_collection(exponent);
                    let address = dynamic::storage::<([u8; 32], u32), RingKeysStatus>(
                        "Members",
                        "RingKeysStatus",
                    );
                    let status = storage
                        .fetch(address, (collection, ring_index))
                        .await
                        .context("read Members.RingKeysStatus")?
                        .decode()
                        .context("decode Members.RingKeysStatus")?;
                    Ok::<_, anyhow::Error>((positions, status))
                }
            },
        ))
        .await?;
        for (positions, status) in statuses {
            for position in positions {
                let VoucherLocation::Included {
                    ring_total,
                    ring_included,
                    ..
                } = &mut vouchers[position].1.location
                else {
                    unreachable!("only included vouchers have ring-status queries");
                };
                *ring_total = Some(status.total);
                *ring_included = Some(status.included);
            }
        }
        Ok(())
    }
}

fn recycler_collection(exponent: i8) -> [u8; 32] {
    let mut identifier = [0u8; 32];
    identifier[..16].copy_from_slice(b"coinage/recycler");
    identifier[16] = exponent as u8;
    identifier
}

fn asset_metadata_key(asset_id: &[u8]) -> Vec<u8> {
    [
        twox_128(b"Assets").as_slice(),
        twox_128(b"Metadata").as_slice(),
        blake2_128(asset_id).as_slice(),
        asset_id,
    ]
    .concat()
}

async fn query_storage_values(
    rpc: &RpcClient,
    block_hash: &str,
    keys: Vec<Vec<u8>>,
) -> Result<HashMap<Vec<u8>, Vec<u8>>> {
    if keys.is_empty() {
        return Ok(HashMap::new());
    }
    let hex_keys = keys
        .iter()
        .map(|key| format!("0x{}", hex::encode(key)))
        .collect::<Vec<_>>();
    let change_sets = rpc
        .request::<Vec<StorageChangeSet>>("state_queryStorageAt", rpc_params![hex_keys, block_hash])
        .await
        .context("RPC state_queryStorageAt")?;
    let mut values = HashMap::new();
    for change_set in change_sets {
        for (key, value) in change_set.changes {
            let Some(value) = value else {
                continue;
            };
            let key = decode_hex(&key).context("decode storage response key")?;
            let value = decode_hex(&value).context("decode storage response value")?;
            values.insert(key, value);
        }
    }
    Ok(values)
}

fn decode_hex(value: &str) -> Result<Vec<u8>> {
    hex::decode(value.strip_prefix("0x").unwrap_or(value)).map_err(Into::into)
}

fn decode_value<T: Decode>(bytes: &[u8], label: &str) -> Result<T> {
    let mut input = bytes;
    let value = T::decode(&mut input).with_context(|| format!("decode {label}"))?;
    if !input.is_empty() {
        bail!("{label} has {} trailing SCALE bytes", input.len());
    }
    Ok(value)
}

fn load_scan_state(path: &Path) -> Result<ScanState> {
    let text = match fs::read_to_string(path) {
        Ok(text) => text,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return Ok(ScanState::default());
        }
        Err(error) => return Err(error).with_context(|| format!("read {}", path.display())),
    };
    let state: ScanState =
        serde_json::from_str(&text).with_context(|| format!("decode {}", path.display()))?;
    if state.version != 1 && state.version != SCAN_STATE_VERSION {
        bail!(
            "{} has unsupported version {}",
            path.display(),
            state.version
        );
    }
    Ok(state)
}

fn save_scan_state(path: &Path, state: &ScanState) -> Result<()> {
    let parent = path
        .parent()
        .with_context(|| format!("{} has no parent directory", path.display()))?;
    fs::create_dir_all(parent).with_context(|| format!("create {}", parent.display()))?;
    let temporary = parent.join(format!("{SCAN_STATE_FILE}.{}.tmp", std::process::id()));
    let text = serde_json::to_string_pretty(state)?;
    let mut file = OpenOptions::new()
        .create(true)
        .truncate(true)
        .write(true)
        .open(&temporary)
        .with_context(|| format!("open {}", temporary.display()))?;
    file.write_all(format!("{text}\n").as_bytes())
        .with_context(|| format!("write {}", temporary.display()))?;
    file.sync_all()
        .with_context(|| format!("sync {}", temporary.display()))?;
    fs::rename(&temporary, path).with_context(|| format!("replace {}", path.display()))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;
    use std::sync::Mutex;

    use super::*;

    struct FakeQuery {
        denomination: Denomination,
        coins: BTreeMap<u32, CoinState>,
        vouchers: BTreeMap<u32, VoucherState>,
        coin_calls: Mutex<Vec<Vec<u32>>>,
        voucher_calls: Mutex<Vec<Vec<u32>>>,
    }

    impl Default for FakeQuery {
        fn default() -> Self {
            Self {
                denomination: Denomination {
                    unit: 10_000,
                    precision: 6,
                    minimum_exponent: 0,
                    maximum_exponent: 14,
                },
                coins: BTreeMap::new(),
                vouchers: BTreeMap::new(),
                coin_calls: Mutex::new(Vec::new()),
                voucher_calls: Mutex::new(Vec::new()),
            }
        }
    }

    #[async_trait]
    impl CoinageQuery for FakeQuery {
        fn denomination(&self) -> Denomination {
            self.denomination
        }

        async fn coins(
            &self,
            _root_entropy: &[u8],
            indices: &[u32],
        ) -> Result<Vec<Option<CoinState>>> {
            self.coin_calls.lock().unwrap().push(indices.to_vec());
            Ok(indices
                .iter()
                .map(|index| self.coins.get(index).copied())
                .collect())
        }

        async fn vouchers(
            &self,
            _root_entropy: &[u8],
            indices: &[u32],
            _known: &BTreeMap<u32, StoredVoucher>,
        ) -> Result<Vec<Option<VoucherState>>> {
            self.voucher_calls.lock().unwrap().push(indices.to_vec());
            Ok(indices
                .iter()
                .map(|index| self.vouchers.get(index).copied())
                .collect())
        }
    }

    #[tokio::test]
    async fn totals_coins_vouchers_and_on_hold_like_cash() {
        let mut query = FakeQuery::default();
        query.coins.insert(
            3,
            CoinState {
                exponent: 6,
                age: 1,
            },
        );
        query.coins.insert(
            501,
            CoinState {
                exponent: 5,
                age: RECYCLE_AT_AGE,
            },
        );
        query.vouchers.insert(
            2,
            VoucherState {
                exponent: 10,
                on_hold: false,
                counted: true,
                location: VoucherLocation::Included {
                    ring_index: 9,
                    ring_position: 2,
                    ring_total: Some(12),
                    ring_included: Some(12),
                },
            },
        );
        query.vouchers.insert(
            700,
            VoucherState {
                exponent: 7,
                on_hold: true,
                counted: true,
                location: VoucherLocation::Onboarding,
            },
        );
        query.vouchers.insert(
            800,
            VoucherState {
                exponent: 12,
                on_hold: false,
                counted: false,
                location: VoucherLocation::Unloaded { ring_index: 4 },
            },
        );
        let mut state = WalletScanState::default();

        let balance = read_with_query_mode(&query, &[0xab; 32], &mut state, false, false)
            .await
            .unwrap();

        assert_eq!(
            balance.balance,
            CashBalance {
                total: "12.48".to_string(),
                on_hold: Some("1.60".to_string()),
            }
        );
        assert_eq!(balance.next_voucher_index, 801);
        assert_eq!(state.highest_coin_index, Some(501));
        assert_eq!(state.highest_voucher_index, Some(800));
        assert_eq!(
            balance.verbose_lines(),
            vec![
                "Coins (2)",
                "  #3 · 2^6 · 0.64 CASH · available · age 1",
                "  #501 · 2^5 · 0.32 CASH · on hold · age 14",
                "Vouchers (3)",
                "  #2 · 2^10 · 10.24 CASH · in recycler · full · ring 9 (12/12 included)",
                "  #700 · 2^7 · 1.28 CASH · pending · degraded",
                "  #800 · 2^12 · 40.96 CASH · unloaded · privacy n/a · ring 4 · excluded from balance",
                "Allocation and ready-at times are shown for locally allocated vouchers; chain-recovered vouchers have no historical timestamps.",
            ]
        );
    }

    #[tokio::test]
    async fn zero_balance_omits_on_hold_detail() {
        let mut state = WalletScanState::default();
        let balance =
            read_with_query_mode(&FakeQuery::default(), &[0xab; 32], &mut state, false, false)
                .await
                .unwrap();

        assert_eq!(balance.balance.total, "0.00");
        assert_eq!(balance.balance.on_hold, None);
        assert_eq!(balance.next_voucher_index, 0);
    }

    #[tokio::test]
    async fn cached_highest_index_recovers_beyond_the_initial_gap() {
        let mut query = FakeQuery::default();
        query.coins.insert(
            2_100,
            CoinState {
                exponent: 0,
                age: 0,
            },
        );
        let mut state = WalletScanState {
            highest_coin_index: Some(2_100),
            ..WalletScanState::default()
        };

        let balance = read_with_query_mode(&query, &[0xab; 32], &mut state, false, false)
            .await
            .unwrap();

        assert_eq!(balance.balance.total, "0.01");
        assert_eq!(state.highest_coin_index, Some(2_100));
        assert!(
            query
                .coin_calls
                .lock()
                .unwrap()
                .iter()
                .any(|indices| indices.contains(&2_100))
        );
    }

    #[tokio::test]
    async fn repeated_recovery_advances_beyond_previous_empty_ranges() {
        let mut query = FakeQuery::default();
        let mut state = WalletScanState::default();
        read_with_query_mode(&query, &[0xab; 32], &mut state, false, false)
            .await
            .unwrap();
        query.coins.insert(
            2_100,
            CoinState {
                exponent: 0,
                age: 0,
            },
        );
        query.vouchers.insert(
            2_100,
            VoucherState {
                exponent: 0,
                on_hold: false,
                counted: true,
                location: VoucherLocation::Included {
                    ring_index: 9,
                    ring_position: 0,
                    ring_total: None,
                    ring_included: None,
                },
            },
        );

        let recovered = read_with_query_mode(&query, &[0xab; 32], &mut state, false, true)
            .await
            .unwrap();
        let first_coin_horizon = state.coin_scan_horizon;
        let first_voucher_horizon = state.voucher_scan_horizon;
        read_with_query_mode(&query, &[0xab; 32], &mut state, false, true)
            .await
            .unwrap();

        assert_eq!(recovered.balance.total, "0.02");
        assert_eq!(first_coin_horizon, Some(4_499));
        assert_eq!(first_voucher_horizon, Some(4_499));
        assert_eq!(state.coin_scan_horizon, Some(6_499));
        assert_eq!(state.voucher_scan_horizon, Some(6_499));
        assert!(
            query
                .coin_calls
                .lock()
                .unwrap()
                .iter()
                .any(|indices| indices.first() == Some(&4_500))
        );
        assert!(
            query
                .voucher_calls
                .lock()
                .unwrap()
                .iter()
                .any(|indices| indices.first() == Some(&4_500))
        );
    }

    #[tokio::test]
    async fn locally_known_vouchers_survive_incomplete_chain_reconstruction() {
        let exponents = [8, 7, 6, 5, 4, 2];
        let mut query = FakeQuery::default();
        let mut state = WalletScanState {
            highest_voucher_index: Some(17),
            ..WalletScanState::default()
        };
        for index in 0..18 {
            let exponent = exponents[index as usize % exponents.len()];
            state
                .vouchers
                .insert(index, StoredVoucher::allocated(exponent, 0, 1_000));
            if index < 6 {
                query.vouchers.insert(
                    index,
                    VoucherState {
                        exponent,
                        on_hold: false,
                        counted: true,
                        location: VoucherLocation::Included {
                            ring_index: 9,
                            ring_position: index,
                            ring_total: None,
                            ring_included: None,
                        },
                    },
                );
            }
        }

        let balance = read_with_query_mode(&query, &[0xab; 32], &mut state, false, false)
            .await
            .unwrap();

        assert_eq!(balance.balance.total, "15.00");
        assert_eq!(balance.balance.on_hold.as_deref(), Some("10.00"));
        assert_eq!(state.vouchers.len(), 18);
    }

    #[tokio::test]
    async fn unloaded_observation_excludes_a_persisted_voucher() {
        let mut query = FakeQuery::default();
        query.vouchers.insert(
            0,
            VoucherState {
                exponent: 8,
                on_hold: false,
                counted: false,
                location: VoucherLocation::Unloaded { ring_index: 3 },
            },
        );
        let mut state = WalletScanState {
            highest_voucher_index: Some(0),
            vouchers: BTreeMap::from([(0, StoredVoucher::allocated(8, 0, 1_000))]),
            ..WalletScanState::default()
        };

        let balance = read_with_query_mode(&query, &[0xab; 32], &mut state, false, false)
            .await
            .unwrap();

        assert_eq!(balance.balance.total, "0.00");
        assert!(!state.vouchers[&0].state.counted);
    }

    #[test]
    fn allocated_vouchers_are_scoped_to_the_active_signer() {
        let temporary = tempfile::tempdir().unwrap();
        let first_entropy = [0x11; 32];
        let second_entropy = [0x22; 32];

        record_allocated_vouchers(Some(temporary.path()), &first_entropy, &[(0, 8, 100, 200)])
            .unwrap();
        record_allocated_vouchers(Some(temporary.path()), &second_entropy, &[(0, 7, 300, 400)])
            .unwrap();

        let state = load_scan_state(&temporary.path().join(SCAN_STATE_FILE)).unwrap();
        assert_eq!(state.wallets.len(), 2);
        assert_eq!(
            state.wallets[&wallet_id(&first_entropy).unwrap()].vouchers[&0]
                .state
                .exponent,
            8
        );
        assert_eq!(
            state.wallets[&wallet_id(&second_entropy).unwrap()].vouchers[&0]
                .state
                .exponent,
            7
        );
    }

    #[test]
    fn version_one_high_water_marks_migrate_to_the_active_signer() {
        let mut state = ScanState {
            version: 1,
            wallets: BTreeMap::new(),
            highest_coin_index: Some(42),
            highest_voucher_index: Some(84),
        };

        let wallet = state.wallet_mut("wallet");

        assert_eq!(wallet.highest_coin_index, Some(42));
        assert_eq!(wallet.highest_voucher_index, Some(84));
        assert_eq!(state.version, SCAN_STATE_VERSION);
        assert_eq!(state.highest_coin_index, None);
        assert_eq!(state.highest_voucher_index, None);
    }

    #[test]
    fn scan_state_round_trips_without_secret_material() {
        let temporary = tempfile::tempdir().unwrap();
        let path = temporary.path().join(SCAN_STATE_FILE);
        let wallet_id = wallet_id(&[0xab; 32]).unwrap();
        let state = ScanState {
            version: SCAN_STATE_VERSION,
            wallets: BTreeMap::from([(
                wallet_id,
                WalletScanState {
                    highest_coin_index: Some(42),
                    highest_voucher_index: Some(84),
                    coin_scan_horizon: Some(999),
                    voucher_scan_horizon: Some(1_999),
                    vouchers: BTreeMap::new(),
                },
            )]),
            highest_coin_index: None,
            highest_voucher_index: None,
        };

        save_scan_state(&path, &state).unwrap();

        assert_eq!(load_scan_state(&path).unwrap(), state);
        let text = fs::read_to_string(path).unwrap();
        assert!(!text.contains("entropy"));
        assert!(!text.contains("mnemonic"));
    }

    #[test]
    fn voucher_timestamps_render_as_utc() {
        assert_eq!(
            format_unix_ms(1_775_000_123_456).unwrap(),
            "2026-03-31T23:35:23.456Z"
        );
    }

    #[test]
    fn full_ring_is_degraded_until_the_local_ready_time() {
        let location = VoucherLocation::Included {
            ring_index: 9,
            ring_position: 2,
            ring_total: Some(12),
            ring_included: Some(12),
        };

        assert_eq!(voucher_detail(location, false).1, "degraded");
        assert_eq!(voucher_detail(location, true).1, "full");
    }

    #[test]
    fn scale_models_match_current_coinage_layout() {
        let coin = decode_value::<OnChainCoin>(&[7, 14, 0], "coin").unwrap();
        assert_eq!(coin.value, 7);
        assert_eq!(coin.age, 14);

        let included =
            decode_value::<RingPosition>(&[1, 9, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0], "member")
                .unwrap();
        assert!(matches!(
            included,
            RingPosition::Included { ring_index: 9, .. }
        ));
    }
}
