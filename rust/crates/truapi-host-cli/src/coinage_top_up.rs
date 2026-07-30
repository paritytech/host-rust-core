//! Testnet Coinage top-up flow for the signing-host `/top-up` command.

use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result, bail};
use bip39::Mnemonic;
use parity_scale_codec::{Compact, Encode};
use rand::rngs::OsRng;
use rand::{Rng, RngCore};
use rustls::SignatureScheme;
use rustls::pki_types::{PrivateKeyDer, PrivatePkcs8KeyDer};
use rustls::sign::SigningKey;
use schnorrkel::{ExpansionMode, Keypair, MiniSecretKey};
use subxt::client::OnlineClient;
use subxt::config::{RpcConfigFor, substrate::SubstrateConfig};
use subxt::dynamic;
use subxt::utils::{AccountId32, MultiAddress, MultiSignature};
use subxt_rpcs::client::RpcClient;
use subxt_rpcs::methods::LegacyRpcMethods;
use truapi_server::host_logic::coinage::derive_voucher_load;
use truapi_server::host_logic::product_account::derive_root_keypair_from_entropy;
use truapi_server::statement_allowance as alloc;
use truapi_server::statement_allowance::extension::{ChainState, EncodedExtension, Metadata};

/// The iOS testnet faucet account used by the Cash top-up service.
const FAUCET_MNEMONIC: &str =
    "fluid truth dirt pulp rhythm decorate truck divert season tray cattle tumble";
const TOP_UP_MINIMUM_UNITS: u128 = 500;
const AS_COINAGE: &str = "AsCoinage";
const INFALLIBLE_UNPAID_SIGNED: &str = "InfallibleUnpaidSigned";
const SR25519_SIGNING_CONTEXT: &[u8] = b"substrate";
const VALUE_TRANSFER_AUTHORIZATION_ENV: &str = "HOST_CLI_VALUE_TRANSFER_AUTH_KEY";
const IOS_VALUE_TRANSFER_AUTHORIZATION_ENV: &str = "W3S_AUTH_KEY";
const MAX_VOUCHER_READY_DELAY_MS: u64 = 6 * 60 * 60 * 1_000;
const ED25519_PKCS8_SEED_PREFIX: &[u8] = &[
    0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x04, 0x22, 0x04, 0x20,
];

/// Result rendered after both top-up transactions finalize successfully.
pub struct TopUpResult {
    pub amount: String,
    pub vouchers: Vec<TopUpVoucher>,
}

/// Wallet-local metadata for one voucher allocated by `/top-up`.
pub struct TopUpVoucher {
    pub index: u32,
    pub exponent: i8,
    pub allocated_at_unix_ms: u64,
    pub ready_at_unix_ms: u64,
}

/// Ed25519 authority used by the iOS app to unlock protected test-asset
/// transfers.
pub struct ValueTransferAuthorizer {
    signing_key: std::sync::Arc<dyn SigningKey>,
}

impl ValueTransferAuthorizer {
    /// Load the same seed injected into iOS builds as `W3S_AUTH_KEY`.
    pub fn from_environment() -> Result<Self> {
        let value = std::env::var(VALUE_TRANSFER_AUTHORIZATION_ENV)
            .or_else(|_| std::env::var(IOS_VALUE_TRANSFER_AUTHORIZATION_ENV))
            .with_context(|| {
                format!(
                    "/top-up requires {VALUE_TRANSFER_AUTHORIZATION_ENV} \
                     (or the iOS-compatible {IOS_VALUE_TRANSFER_AUTHORIZATION_ENV})"
                )
            })?;
        let seed = hex::decode(value.trim().strip_prefix("0x").unwrap_or(value.trim()))
            .context("value-transfer authorization key must be hex")?;
        if seed.len() != 32 {
            bail!(
                "value-transfer authorization key must be a 32-byte Ed25519 seed, got {} bytes",
                seed.len()
            );
        }
        Self::from_seed(&seed)
    }

    fn from_seed(seed: &[u8]) -> Result<Self> {
        let mut pkcs8 = Vec::with_capacity(ED25519_PKCS8_SEED_PREFIX.len() + seed.len());
        pkcs8.extend_from_slice(ED25519_PKCS8_SEED_PREFIX);
        pkcs8.extend_from_slice(seed);
        let private_key = PrivateKeyDer::Pkcs8(PrivatePkcs8KeyDer::from(pkcs8));
        let signing_key = rustls::crypto::ring::sign::any_supported_type(&private_key)
            .context("initialize Ed25519 value-transfer authorization key")?;
        Ok(Self { signing_key })
    }

    fn sign(&self, message: &[u8]) -> Result<Vec<u8>> {
        let signer = self
            .signing_key
            .choose_scheme(&[SignatureScheme::ED25519])
            .context("value-transfer key does not support Ed25519")?;
        signer
            .sign(message)
            .context("sign value-transfer authorization")
    }
}

#[derive(Debug, Clone, Copy, Encode)]
enum CodecPreservation {
    Expendable,
}

#[derive(Debug, Clone, Copy, Encode)]
struct UnpaidLoadInput {
    preservation: CodecPreservation,
    value: i8,
    member_key: [u8; 32],
    proof_of_ownership: [u8; 64],
}

/// Transfer 5.00 of the configured test asset to a temporary holder, then
/// convert it into vouchers owned by the active wallet.
pub async fn submit(
    people_ws: &str,
    root_entropy: &[u8],
    first_voucher_index: u32,
    authorizer: &ValueTransferAuthorizer,
) -> Result<TopUpResult> {
    let rpc = alloc::rpc::RpcClient::connect(people_ws)
        .await
        .map_err(anyhow::Error::msg)?;
    let metadata = alloc::fetch_metadata(&rpc)
        .await
        .map_err(anyhow::Error::msg)?;
    let chain_state = alloc::fetch_chain_state(&rpc)
        .await
        .map_err(anyhow::Error::msg)?;

    let native_rpc = RpcClient::from_insecure_url(people_ws)
        .await
        .with_context(|| format!("connect Coinage top-up RPC {people_ws}"))?;
    let client = OnlineClient::<SubstrateConfig>::from_rpc_client(native_rpc.clone())
        .await
        .context("initialize Coinage top-up client")?;
    let at = client
        .at_current_block()
        .await
        .context("resolve finalized Coinage top-up block")?;
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
    let max_batch = constants
        .entry(dynamic::constant::<u32>("Coinage", "MaxBatchUnpaidLoad"))
        .context("read Coinage.MaxBatchUnpaidLoad")?;
    let exponents =
        denomination_breakdown(TOP_UP_MINIMUM_UNITS, minimum_exponent, maximum_exponent)?;
    if exponents.len() > max_batch as usize {
        bail!(
            "5.00 CASH requires {} vouchers but the runtime permits {max_batch}",
            exponents.len()
        );
    }
    let allocated_at_unix_ms = current_unix_ms()?;
    let mut rng = OsRng;
    let vouchers = allocate_voucher_metadata(
        first_voucher_index,
        &exponents,
        allocated_at_unix_ms,
        &mut rng,
    )?;
    let amount_planks = unit
        .checked_mul(TOP_UP_MINIMUM_UNITS)
        .context("Coinage top-up amount overflows")?;

    let finalized_hash = rpc.finalized_head().await.map_err(anyhow::Error::msg)?;
    let underlying_entry = at
        .storage()
        .entry(dynamic::storage::<(), ()>("Coinage", "UnderlyingAssetId"))
        .context("resolve Coinage.UnderlyingAssetId")?;
    let underlying_key = underlying_entry
        .fetch_key(())
        .context("encode Coinage.UnderlyingAssetId key")?;
    let underlying_asset = rpc
        .get_storage_at(&underlying_key, &finalized_hash)
        .await
        .map_err(anyhow::Error::msg)?
        .context("Coinage underlying asset is not configured")?;

    let temporary = random_keypair()?;
    let temporary_account = temporary.public.to_bytes();
    let faucet = faucet_keypair()?;
    let legacy = LegacyRpcMethods::<RpcConfigFor<SubstrateConfig>>::new(native_rpc.clone());

    // Prepare and encode the voucher load before moving any faucet funds. This
    // catches derivation or metadata incompatibilities while the temporary
    // account is still empty.
    let loads = build_voucher_loads(
        root_entropy,
        first_voucher_index,
        temporary_account,
        &exponents,
    )?;
    let temporary_nonce = legacy
        .system_account_next_index(&AccountId32(temporary_account))
        .await
        .context("read temporary top-up account nonce")?;
    let load_call = build_unpaid_load_call(&metadata, &loads)?;
    let as_coinage_variant = metadata
        .extension_info_variant_index(AS_COINAGE, INFALLIBLE_UNPAID_SIGNED)
        .map_err(anyhow::Error::msg)?;
    let as_coinage_extra = encode_as_coinage(as_coinage_variant, temporary_nonce)?;
    let load = build_signed_v4(
        &metadata,
        chain_state,
        &temporary,
        temporary_nonce,
        &load_call,
        authorizer,
        Some(as_coinage_extra),
    )?;

    let faucet_account = AccountId32(faucet.public.to_bytes());
    let faucet_nonce = legacy
        .system_account_next_index(&faucet_account)
        .await
        .context("read top-up faucet nonce")?;
    let transfer_call = build_asset_transfer_call(
        &metadata,
        &underlying_asset,
        temporary_account,
        amount_planks,
    )?;
    let transfer = build_signed_v4(
        &metadata,
        chain_state,
        &faucet,
        faucet_nonce,
        &transfer_call,
        authorizer,
        None,
    )?;
    at.transactions()
        .from_bytes(transfer)
        .submit_and_watch()
        .await
        .context("submit top-up asset transfer")?
        .wait_for_finalized_success()
        .await
        .context("finalize top-up asset transfer")?;

    at.transactions()
        .from_bytes(load)
        .submit_and_watch()
        .await
        .context("submit Coinage voucher load")?
        .wait_for_finalized_success()
        .await
        .context("finalize Coinage voucher load")?;

    Ok(TopUpResult {
        amount: "5.00".to_string(),
        vouchers,
    })
}

fn allocate_voucher_metadata<R: Rng + ?Sized>(
    first_voucher_index: u32,
    exponents: &[i8],
    allocated_at_unix_ms: u64,
    rng: &mut R,
) -> Result<Vec<TopUpVoucher>> {
    exponents
        .iter()
        .enumerate()
        .map(|(offset, &exponent)| {
            let offset = u32::try_from(offset).context("too many Coinage vouchers")?;
            let index = first_voucher_index
                .checked_add(offset)
                .context("Coinage voucher derivation indices are exhausted")?;
            let ready_delay = rng.gen_range(0..=MAX_VOUCHER_READY_DELAY_MS);
            let ready_at_unix_ms = allocated_at_unix_ms
                .checked_add(ready_delay)
                .context("Coinage voucher ready-at time overflows")?;
            Ok(TopUpVoucher {
                index,
                exponent,
                allocated_at_unix_ms,
                ready_at_unix_ms,
            })
        })
        .collect()
}

fn current_unix_ms() -> Result<u64> {
    let milliseconds = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .context("system clock is before the Unix epoch")?
        .as_millis();
    u64::try_from(milliseconds).context("system time exceeds u64 milliseconds")
}

fn random_keypair() -> Result<Keypair> {
    let mut seed = [0u8; 32];
    OsRng.fill_bytes(&mut seed);
    Ok(MiniSecretKey::from_bytes(&seed)
        .map_err(|error| anyhow::anyhow!("generate temporary top-up key: {error:?}"))?
        .expand_to_keypair(ExpansionMode::Ed25519))
}

fn faucet_keypair() -> Result<Keypair> {
    let entropy = Mnemonic::parse(FAUCET_MNEMONIC)
        .context("parse built-in testnet top-up faucet")?
        .to_entropy();
    derive_root_keypair_from_entropy(&entropy)
        .map_err(|error| anyhow::anyhow!("derive testnet top-up faucet: {error}"))
}

fn denomination_breakdown(
    minimum_units: u128,
    minimum_exponent: i8,
    maximum_exponent: i8,
) -> Result<Vec<i8>> {
    if minimum_exponent > maximum_exponent {
        bail!("invalid Coinage denomination range {minimum_exponent}..={maximum_exponent}");
    }
    if maximum_exponent < 0 {
        bail!("5.00 CASH cannot be represented by sub-unit denominations");
    }
    let mut remaining = minimum_units;
    let mut output = Vec::new();
    for exponent in (minimum_exponent.max(0)..=maximum_exponent).rev() {
        let value = 1u128
            .checked_shl(exponent as u32)
            .with_context(|| format!("Coinage denomination 2^{exponent} overflows"))?;
        while remaining >= value {
            remaining -= value;
            output.push(exponent);
        }
    }
    if remaining != 0 {
        bail!(
            "5.00 CASH cannot be represented by runtime denominations \
             {minimum_exponent}..={maximum_exponent}"
        );
    }
    Ok(output)
}

fn build_voucher_loads(
    root_entropy: &[u8],
    first_index: u32,
    external_asset_holder: [u8; 32],
    exponents: &[i8],
) -> Result<Vec<UnpaidLoadInput>> {
    exponents
        .iter()
        .enumerate()
        .map(|(offset, exponent)| {
            let offset = u32::try_from(offset).context("too many Coinage vouchers")?;
            let index = first_index
                .checked_add(offset)
                .context("Coinage voucher derivation indices are exhausted")?;
            let load = derive_voucher_load(root_entropy, index, &external_asset_holder)
                .with_context(|| format!("derive Coinage voucher {index}"))?;
            Ok(UnpaidLoadInput {
                preservation: CodecPreservation::Expendable,
                value: *exponent,
                member_key: load.member,
                proof_of_ownership: load.proof_of_ownership,
            })
        })
        .collect()
}

fn build_asset_transfer_call(
    metadata: &Metadata,
    underlying_asset: &[u8],
    target: [u8; 32],
    amount: u128,
) -> Result<Vec<u8>> {
    let mut call = metadata
        .call_indices("Assets", "transfer")
        .map_err(anyhow::Error::msg)?
        .to_vec();
    call.extend_from_slice(underlying_asset);
    MultiAddress::<AccountId32, ()>::Id(AccountId32(target)).encode_to(&mut call);
    Compact(amount).encode_to(&mut call);
    Ok(call)
}

fn build_unpaid_load_call(metadata: &Metadata, items: &[UnpaidLoadInput]) -> Result<Vec<u8>> {
    let mut call = metadata
        .call_indices("Coinage", "load_recycler_with_external_asset_unpaid_batch")
        .map_err(anyhow::Error::msg)?
        .to_vec();
    items.encode_to(&mut call);
    Ok(call)
}

fn encode_as_coinage(variant: u8, nonce: u64) -> Result<Vec<u8>> {
    let nonce = u32::try_from(nonce).context("Coinage nonce exceeds u32")?;
    Ok([vec![1, variant], nonce.encode()].concat())
}

fn build_signed_v4(
    metadata: &Metadata,
    mut chain_state: ChainState,
    signer: &Keypair,
    nonce: u64,
    call_data: &[u8],
    authorizer: &ValueTransferAuthorizer,
    as_coinage_extra: Option<Vec<u8>>,
) -> Result<Vec<u8>> {
    chain_state.nonce = u32::try_from(nonce).context("account nonce exceeds u32")?;
    let mut extensions = metadata.encode_signed_extensions(&chain_state);
    if let Some(extra) = as_coinage_extra {
        metadata
            .replace_signed_extension_extra(&mut extensions, AS_COINAGE, extra)
            .map_err(anyhow::Error::msg)?;
    }
    let authorization_index = metadata
        .extension_index("AuthorizeValueTransfer")
        .context("AuthorizeValueTransfer extension not found in metadata")?;
    let authorization_payload =
        extension_implication_payload(call_data, &extensions, authorization_index);
    let authorization_hash = sp_crypto_hashing::blake2_256(&authorization_payload);
    let authorization_signature = authorizer.sign(&authorization_hash)?;
    if authorization_signature.len() != 64 {
        bail!(
            "Ed25519 value-transfer signature is {} bytes, expected 64",
            authorization_signature.len()
        );
    }
    let mut authorization_extra = Vec::with_capacity(65);
    authorization_extra.push(1);
    authorization_extra.extend_from_slice(&authorization_signature);
    metadata
        .replace_signed_extension_extra(
            &mut extensions,
            "AuthorizeValueTransfer",
            authorization_extra,
        )
        .map_err(anyhow::Error::msg)?;

    let signer_payload = signer_payload(call_data, &extensions);
    let signature =
        signer
            .secret
            .sign_simple(SR25519_SIGNING_CONTEXT, &signer_payload, &signer.public);
    let address = MultiAddress::<AccountId32, u32>::Id(AccountId32(signer.public.to_bytes()));
    let signature = MultiSignature::Sr25519(signature.to_bytes());

    let mut inner = vec![0x84];
    address.encode_to(&mut inner);
    signature.encode_to(&mut inner);
    for extension in extensions {
        inner.extend_from_slice(&extension.extra);
    }
    inner.extend_from_slice(call_data);
    Ok(inner.encode())
}

fn extension_implication_payload(
    call_data: &[u8],
    extensions: &[EncodedExtension],
    extension_index: usize,
) -> Vec<u8> {
    let tail = &extensions[extension_index + 1..];
    let mut payload = Vec::with_capacity(1 + call_data.len());
    // Transaction-extension pipeline version. iOS adds this same zero byte
    // when signing a V4 inherited implication.
    payload.push(0);
    payload.extend_from_slice(call_data);
    for extension in tail {
        payload.extend_from_slice(&extension.extra);
    }
    for extension in tail {
        payload.extend_from_slice(&extension.additional_signed);
    }
    payload
}

fn signer_payload(call_data: &[u8], extensions: &[EncodedExtension]) -> Vec<u8> {
    let mut payload = Vec::with_capacity(call_data.len());
    payload.extend_from_slice(call_data);
    for extension in extensions {
        payload.extend_from_slice(&extension.extra);
    }
    for extension in extensions {
        payload.extend_from_slice(&extension.additional_signed);
    }
    if payload.len() > 256 {
        sp_crypto_hashing::blake2_256(&payload).to_vec()
    } else {
        payload
    }
}

#[cfg(test)]
mod tests {
    use rand::SeedableRng;
    use rand::rngs::StdRng;

    use super::*;

    const FIXTURE: &[u8] = include_bytes!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../truapi-server/tests/fixtures/paseo-next-v2-metadata.scale"
    ));

    #[test]
    fn five_cash_breaks_down_like_the_ios_wallet() {
        assert_eq!(
            denomination_breakdown(500, 0, 14).unwrap(),
            vec![8, 7, 6, 5, 4, 2]
        );
    }

    #[test]
    fn denomination_breakdown_respects_runtime_bounds() {
        assert!(denomination_breakdown(1, 1, 14).is_err());
        assert!(denomination_breakdown(500, 4, 14).is_err());
        assert!(denomination_breakdown(500, 14, 0).is_err());
    }

    #[test]
    fn live_fixture_resolves_top_up_calls_and_coinage_authorization() {
        let metadata = Metadata::decode(FIXTURE).unwrap();

        assert_eq!(
            metadata.call_indices("Assets", "transfer").unwrap(),
            [14, 8]
        );
        assert_eq!(
            metadata
                .call_indices("Coinage", "load_recycler_with_external_asset_unpaid_batch")
                .unwrap(),
            [68, 16],
        );
        assert_eq!(
            metadata
                .extension_info_variant_index(AS_COINAGE, INFALLIBLE_UNPAID_SIGNED)
                .unwrap(),
            5,
        );
        assert_eq!(encode_as_coinage(5, 9).unwrap(), [1, 5, 9, 0, 0, 0]);
    }

    #[test]
    fn voucher_batch_uses_consecutive_wallet_indices() {
        let owner = [0x42; 32];
        let loads = build_voucher_loads(&[0xab; 32], 7, owner, &[8, 2]).unwrap();
        let first = derive_voucher_load(&[0xab; 32], 7, &owner).unwrap();
        let second = derive_voucher_load(&[0xab; 32], 8, &owner).unwrap();

        assert_eq!(loads[0].member_key, first.member);
        assert_eq!(loads[1].member_key, second.member);
        assert_eq!(loads[0].value, 8);
        assert_eq!(loads[1].value, 2);
    }

    #[test]
    fn allocated_voucher_metadata_uses_consecutive_indices_and_mobile_ready_delay() {
        let mut rng = StdRng::seed_from_u64(42);

        let vouchers = allocate_voucher_metadata(7, &[8, 2], 1_000_000, &mut rng).unwrap();

        assert_eq!(
            vouchers
                .iter()
                .map(|voucher| (voucher.index, voucher.exponent))
                .collect::<Vec<_>>(),
            [(7, 8), (8, 2)]
        );
        assert!(vouchers.iter().all(|voucher| {
            (1_000_000..=1_000_000 + MAX_VOUCHER_READY_DELAY_MS).contains(&voucher.ready_at_unix_ms)
        }));
    }

    #[test]
    fn value_transfer_authorizer_matches_the_ed25519_reference_vector() {
        let seed = hex::decode("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")
            .unwrap();
        let authorizer = ValueTransferAuthorizer::from_seed(&seed).unwrap();

        assert_eq!(
            hex::encode(authorizer.sign(&[]).unwrap()),
            "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155\
             5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"
        );
    }

    #[test]
    fn value_transfer_implication_has_version_call_and_extension_tail() {
        let extensions = vec![
            EncodedExtension {
                extra: vec![0xaa],
                additional_signed: vec![0xbb],
            },
            EncodedExtension {
                extra: vec![0x11, 0x12],
                additional_signed: vec![0x21],
            },
            EncodedExtension {
                extra: vec![0x31],
                additional_signed: vec![0x41, 0x42],
            },
        ];

        assert_eq!(
            extension_implication_payload(&[0x01, 0x02], &extensions, 0),
            [0x00, 0x01, 0x02, 0x11, 0x12, 0x31, 0x21, 0x41, 0x42]
        );
    }
}
