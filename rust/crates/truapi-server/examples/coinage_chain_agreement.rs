//! Check the coinage layer's assumptions against a real runtime.
//!
//! Everything else about coinage is verified offline: the domain model by unit
//! tests, the whole pipeline by `tests/coinage_lifecycle.rs`. Those prove the
//! layer is self-consistent. They cannot prove it agrees with the chain, because
//! a fake encodes our own assumptions.
//!
//! This example asks the questions only a node can answer, and asks them
//! read-only — no signing, no submission, nothing that costs a coin:
//!
//! 1. Do the constants we hard-code as the reference runtime match what the
//!    chain reports?
//! 2. Do the coinage calls exist under the names we resolve them by?
//! 3. Does the `AsCoinage` extension exist, and what are its variant indices?
//! 4. Does our derivation scheme find coins the chain actually holds?
//!
//! Question 3 is the important one. Five of the six extension variants have
//! never been accepted by a runtime; the encoding was read off the pallet
//! source. This confirms at least that the variants exist and where they sit.
//!
//! ```text
//! cargo run --example coinage_chain_agreement
//! cargo run --example coinage_chain_agreement -- --url wss://host --scan 200
//! COINAGE_ENTROPY=0x… cargo run --example coinage_chain_agreement
//! ```
//!
//! Without `COINAGE_ENTROPY` the derivation check is skipped and reported as
//! skipped, not passed.

use std::time::Duration;

use parity_scale_codec::Decode;

use truapi_server::coinage::storage::{
    ChainCoin, coins_by_owner_key, collections_key, paid_token_collection_id,
    paid_token_collections_created_key,
};
use truapi_server::coinage::tokens::paid_period;
use truapi_server::host_logic::coinage::chain_constants::next_people_paseo;
use truapi_server::host_logic::coinage::derivation;
use truapi_server::host_logic::coinage::types::{CoinAge, CoinIndex, PurseId, Timestamp};
use truapi_server::statement_allowance::extension::Metadata;
use truapi_server::statement_allowance::fetch_metadata;
use truapi_server::statement_allowance::rpc::RpcClient;

/// People chain on the CLI host's default network.
const DEFAULT_URL: &str = "wss://paseo-people-next-system-rpc.polkadot.io";

/// Coinage dispatchables the layer resolves by name.
const CALLS: &[&str] = &[
    "split",
    "transfer",
    "load_recycler_with_coin",
    "unload_recycler_into_coins",
    "unload_recycler_into_external_asset_and_vouchers",
    "load_recycler_with_external_asset_unpaid_batch",
];

/// `AsCoinageInfo` variants the layer encodes.
const EXTENSION_VARIANTS: &[&str] = &[
    "AsCoin",
    "AsUnloadTokenPeople",
    "AsUnloadTokenLitePeople",
    "AsUnloadTokenPaid",
    "AsUnloadTokenFromOutput",
    "InfallibleUnpaidSigned",
];

/// Tally of what agreed, what did not, and what could not be checked.
#[derive(Default)]
struct Report {
    agreed: usize,
    disagreed: Vec<String>,
    skipped: Vec<String>,
}

impl Report {
    fn check(&mut self, label: &str, expected: impl std::fmt::Debug, actual: impl std::fmt::Debug) {
        let expected = format!("{expected:?}");
        let actual = format!("{actual:?}");
        if expected == actual {
            self.agreed += 1;
            println!("  ok    {label}: {actual}");
        } else {
            println!("  DIFF  {label}: expected {expected}, chain says {actual}");
            self.disagreed
                .push(format!("{label}: expected {expected}, chain says {actual}"));
        }
    }

    fn note(&mut self, label: &str, detail: impl std::fmt::Display) {
        self.agreed += 1;
        println!("  ok    {label}: {detail}");
    }

    fn fail(&mut self, label: &str, detail: impl std::fmt::Display) {
        println!("  FAIL  {label}: {detail}");
        self.disagreed.push(format!("{label}: {detail}"));
    }

    fn skip(&mut self, label: &str, why: &str) {
        println!("  skip  {label}: {why}");
        self.skipped.push(label.to_string());
    }

    /// Compare a constant the chain may not expose at all.
    ///
    /// Absent and zero are different answers, and conflating them hides the
    /// more interesting one: a value the pallet declares without
    /// `#[pallet::constant]` cannot be discovered at runtime, so a host has to
    /// carry it as configuration and will not notice a runtime changing it.
    fn check_constant<T: std::fmt::Debug + PartialEq>(
        &mut self,
        label: &str,
        expected: T,
        observed: Option<T>,
    ) {
        match observed {
            None => {
                println!("  ABSENT {label}: not exposed in metadata (expected {expected:?})");
                self.disagreed
                    .push(format!("{label}: not exposed in metadata"));
            }
            Some(actual) => self.check(label, expected, actual),
        }
    }
}

/// Decode a SCALE-encoded pallet constant.
fn constant<T: Decode>(metadata: &Metadata, name: &str) -> Option<T> {
    let bytes = metadata.constant("Coinage", name)?;
    T::decode(&mut &bytes[..]).ok()
}

fn arg(name: &str) -> Option<String> {
    let mut args = std::env::args().skip(1);
    while let Some(candidate) = args.next() {
        if candidate == name {
            return args.next();
        }
    }
    None
}

/// The chain's own clock, in milliseconds since the epoch.
///
/// Read from `Timestamp::Now` rather than taken from the local clock, because the
/// period a paid token belongs to is decided by the runtime's notion of now. Local
/// time would agree in practice and would be wrong in principle — and this check
/// exists precisely to catch being wrong about the period.
async fn chain_now(rpc: &RpcClient) -> Result<Timestamp, String> {
    let key = [
        sp_crypto_hashing::twox_128(b"Timestamp").as_slice(),
        sp_crypto_hashing::twox_128(b"Now").as_slice(),
    ]
    .concat();
    let raw = rpc
        .get_storage(&key)
        .await
        .map_err(|error| format!("reading Timestamp::Now: {error}"))?
        .ok_or_else(|| "Timestamp::Now is absent".to_string())?;
    let millis =
        u64::decode(&mut &raw[..]).map_err(|error| format!("decoding Timestamp::Now: {error}"))?;

    Ok(Timestamp(millis))
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let url = arg("--url").unwrap_or_else(|| DEFAULT_URL.to_string());
    let scan_limit: u32 = arg("--scan")
        .and_then(|value| value.parse().ok())
        .unwrap_or(32);

    println!("coinage chain agreement");
    println!("  url {url}");

    let rpc = RpcClient::connect(&url).await?;
    let metadata = fetch_metadata(&rpc).await?;
    let mut report = Report::default();

    // -- 1. constants ------------------------------------------------------
    println!("\nconstants (expected values are `next_people_paseo()`)");
    let reference = next_people_paseo();

    report.check_constant(
        "MinimumExponent",
        reference.minimum_exponent,
        constant::<i8>(&metadata, "MinimumExponent"),
    );
    report.check_constant(
        "MaximumExponent",
        reference.maximum_exponent,
        constant::<i8>(&metadata, "MaximumExponent"),
    );
    report.check_constant(
        "MaximumAge",
        reference.maximum_age,
        constant::<u16>(&metadata, "MaximumAge").map(CoinAge),
    );
    report.check_constant(
        "MaxSplitOutputs",
        reference.max_split_outputs,
        constant::<u32>(&metadata, "MaxSplitOutputs"),
    );
    report.check_constant(
        "MaxConsolidation",
        reference.max_consolidation,
        constant::<u32>(&metadata, "MaxConsolidation"),
    );
    report.check_constant(
        "RecyclerExpirationTime",
        reference.recycler_expiration_time,
        constant::<u32>(&metadata, "RecyclerExpirationTime")
            .map(|secs| Duration::from_secs(u64::from(secs))),
    );
    report.check_constant(
        "UnloadTokenTimePeriod",
        reference.unload_token_period,
        constant::<u32>(&metadata, "UnloadTokenTimePeriodPeopleLitePeople")
            .map(|secs| Duration::from_secs(u64::from(secs))),
    );
    report.check_constant(
        "MaxFreeUnloadTokensPerTimePeriod",
        reference.max_free_unload_tokens_per_period,
        constant::<u32>(&metadata, "MaxFreeUnloadTokensPerTimePeriod"),
    );
    report.check_constant(
        "MaxBatchUnpaidLoad",
        reference.max_batch_unpaid_load,
        constant::<u32>(&metadata, "MaxBatchUnpaidLoad"),
    );
    report.check_constant(
        "UnderlyingAssetUnit",
        reference.underlying_asset_unit,
        constant::<u128>(&metadata, "UnderlyingAssetUnit"),
    );
    report.check_constant(
        "CoinFailureLockPeriod",
        reference.coin_failure_lock_period,
        constant::<u64>(&metadata, "CoinFailureLockPeriod").map(Duration::from_secs),
    );
    report.check_constant(
        "PaidUnloadTokenTimePeriod",
        reference.paid_unload_token_period,
        constant::<u32>(&metadata, "PaidUnloadTokenTimePeriod")
            .map(|secs| Duration::from_secs(u64::from(secs))),
    );
    report.check_constant(
        "PaidUnloadTokenRingExpirationTime",
        reference.paid_unload_token_ring_expiration,
        constant::<u32>(&metadata, "PaidUnloadTokenRingExpirationTime")
            .map(|secs| Duration::from_secs(u64::from(secs))),
    );

    match reference.validate() {
        Ok(()) => report.note(
            "validate",
            format!(
                "reference config supported; recycle at age {:?}, largest coin {} cents",
                reference.recycle_at_age(),
                reference
                    .largest_denomination()
                    .map(|d| d.value().cents())
                    .unwrap_or_default()
            ),
        ),
        Err(error) => report.fail("validate", error),
    }

    // -- 2. call indices ---------------------------------------------------
    println!("\ncoinage calls (resolved by name, never hard-coded)");
    for call in CALLS {
        match metadata.call_indices("Coinage", call) {
            Ok([pallet, index]) => {
                report.note(call, format!("pallet {pallet}, call {index}"));
            }
            Err(error) => report.fail(call, error),
        }
    }

    // -- 3. AsCoinage extension --------------------------------------------
    println!("\nAsCoinage extension variants");
    for variant in EXTENSION_VARIANTS {
        match metadata.extension_info_variant_index("AsCoinage", variant) {
            Ok(index) => report.note(variant, format!("variant index {index}")),
            Err(error) => report.fail(variant, error),
        }
    }

    // -- 4. the paid unload-token collection identifier --------------------
    //
    // The one fact in this layer that came out of pallet source rather than out
    // of metadata, and the only way to confirm it is to derive the identifier and
    // see whether the members pallet actually has a collection under it. A wrong
    // prefix, a dropped `!` or the wrong endianness all produce the same silent
    // symptom — an absent key, read as "not a member" — so this check is the
    // difference between believing the fallback works and knowing it does.
    println!("\npaid unload-token ring (identifier derived from pallet source)");
    match chain_now(&rpc).await {
        Err(error) => report.fail("paid-token period", error),
        Ok(now) => match paid_period(now, &reference) {
            Err(error) => report.fail("paid-token period", error),
            Ok(period) => {
                report.note("paid-token period", format!("period {period} at {now:?}"));

                let created = rpc
                    .get_storage(&paid_token_collections_created_key(period))
                    .await?;
                match created {
                    Some(_) => report.note(
                        "PaidTokenCollectionsCreated",
                        format!("period {period} is created (big-endian key agrees)"),
                    ),
                    None => report.skip(
                        "PaidTokenCollectionsCreated",
                        "absent — either the pallet has not created this period yet, or the \
                         big-endian period key is wrong",
                    ),
                }

                // The decisive one: pallet-members stores a collection under
                // exactly this 32-byte identifier, so a hit proves the whole
                // derivation, not just its prefix.
                let collection = paid_token_collection_id(period);
                match rpc.get_storage(&collections_key(&collection)).await? {
                    Some(_) => report.note(
                        "Members.Collections[paid]",
                        format!("0x{} resolves to a collection", hex::encode(collection)),
                    ),
                    None => report.fail(
                        "Members.Collections[paid]",
                        format!(
                            "no collection at 0x{} — the identifier this layer derives is not \
                             the one the pallet uses",
                            hex::encode(collection)
                        ),
                    ),
                }
            }
        },
    }

    // -- 5. derivation -----------------------------------------------------
    println!("\nderivation (//coinage//coin//<purse>//<page>//<index>)");
    match std::env::var("COINAGE_ENTROPY") {
        Err(_) => report.skip(
            "coin discovery",
            "set COINAGE_ENTROPY=0x… to probe a real wallet",
        ),
        Ok(raw) => {
            let entropy = hex::decode(raw.trim_start_matches("0x"))?;
            let mut found = 0usize;

            for index in 0..scan_limit {
                let account =
                    derivation::coin_account_id(&entropy, PurseId::MAIN, CoinIndex(index))?;
                let value = rpc.get_storage(&coins_by_owner_key(&account)).await?;

                if let Some(bytes) = value {
                    let coin = ChainCoin::decode(&mut &bytes[..])?;
                    println!(
                        "  found index {index}: 2^{} cents, age {}",
                        coin.value, coin.age
                    );
                    found += 1;
                }
            }

            if found > 0 {
                report.note(
                    "coin discovery",
                    format!("{found} of {scan_limit} probed indices hold coins"),
                );
            } else {
                report.skip(
                    "coin discovery",
                    "no coins under this derivation — inconclusive unless the wallet is known to hold some",
                );
            }
        }
    }

    // -- summary -----------------------------------------------------------
    println!("\n{} checks agreed", report.agreed);
    if !report.skipped.is_empty() {
        println!(
            "{} skipped: {}",
            report.skipped.len(),
            report.skipped.join(", ")
        );
    }
    if report.disagreed.is_empty() {
        println!("no disagreements");
        Ok(())
    } else {
        println!("{} DISAGREEMENTS:", report.disagreed.len());
        for entry in &report.disagreed {
            println!("  - {entry}");
        }
        Err("the chain disagrees with the layer's assumptions".into())
    }
}
