//! Pricing an assembled extrinsic.
//!
//! Needed for one decision only: the ceiling an unload may take out of its own
//! output when the fee account cannot pay (§6.6). That ceiling has to cover the
//! fee the runtime will actually charge, and the fee depends on the extrinsic's
//! own bytes — including the ceiling itself, which sits inside the call.
//!
//! The circularity is resolved by pricing real bytes twice rather than guessing a
//! length once. `u128` is fixed-width in SCALE, so raising the ceiling does not
//! change the extrinsic's length; a second pass therefore converges immediately,
//! and the second pass exists only to catch the case where a runtime prices the
//! *value* of a field rather than its size.
//!
//! The runtime API's return type is not in the metadata type registry — nothing on
//! chain describes `RuntimeDispatchInfo` — so its layout is decoded by hand:
//! `Weight { ref_time: Compact<u64>, proof_size: Compact<u64> }`, a one-byte
//! dispatch class, then the fee as a `u128`. Decoded field by field rather than by
//! taking the trailing sixteen bytes, so a runtime that changes the shape fails
//! loudly instead of pricing garbage.

use core::future::Future;

use parity_scale_codec::{Compact, Decode};
use serde_json::json;

use crate::host_logic::coinage::error::CoinageError;
use crate::runtime::statement_allowance::rpc::RpcClient;

/// Runtime API that prices an extrinsic.
const QUERY_INFO: &str = "TransactionPaymentApi_query_info";

/// How many times to re-price a ceiling before accepting it.
const CEILING_PASSES: usize = 2;

/// The fee the runtime would charge for `extrinsic`.
pub async fn estimate(rpc: &RpcClient, extrinsic: &[u8]) -> Result<u128, CoinageError> {
    let at = rpc
        .finalized_head()
        .await
        .map_err(|error| CoinageError::SubscriptionError(error.to_string()))?;

    // The API takes `(uxt, len)`. `extrinsic` is already the SCALE-encoded
    // extrinsic, length prefix included, which is exactly what `uxt` decodes as.
    let mut payload = extrinsic.to_vec();
    payload.extend((extrinsic.len() as u32).to_le_bytes());

    let result = rpc
        .call(
            "state_call",
            json!([QUERY_INFO, format!("0x{}", hex::encode(&payload)), at]),
        )
        .await
        .map_err(|error| CoinageError::SubscriptionError(error.to_string()))?;
    let encoded = result
        .as_str()
        .ok_or_else(|| {
            CoinageError::Internal("state_call returned a non-string result".to_string())
        })
        .and_then(|hex_str| {
            hex::decode(hex_str.strip_prefix("0x").unwrap_or(hex_str)).map_err(|error| {
                CoinageError::Internal(format!("decoding the fee estimate: {error}"))
            })
        })?;

    decode_partial_fee(&encoded)
}

/// Decode `RuntimeDispatchInfo` and return its fee.
fn decode_partial_fee(encoded: &[u8]) -> Result<u128, CoinageError> {
    let mut cursor = encoded;
    let malformed = |field: &str| {
        CoinageError::Internal(format!(
            "the runtime's fee estimate is not a RuntimeDispatchInfo: {field}"
        ))
    };

    let Compact(_ref_time) =
        Compact::<u64>::decode(&mut cursor).map_err(|_| malformed("weight"))?;
    let Compact(_proof_size) =
        Compact::<u64>::decode(&mut cursor).map_err(|_| malformed("proof size"))?;
    let _class = u8::decode(&mut cursor).map_err(|_| malformed("dispatch class"))?;
    let fee = u128::decode(&mut cursor).map_err(|_| malformed("partial fee"))?;

    Ok(fee)
}

/// Build an extrinsic whose own fee ceiling covers what the runtime will charge.
///
/// `build` is called with a candidate ceiling and returns the extrinsic carrying
/// it. The first pass prices a zero ceiling; each later pass prices the bytes the
/// previous ceiling produced. Settles as soon as the ceiling covers the price.
pub async fn ceiling<F, Fut>(rpc: &RpcClient, build: F) -> Result<Vec<u8>, CoinageError>
where
    F: Fn(u128) -> Fut,
    Fut: Future<Output = Result<Vec<u8>, CoinageError>>,
{
    let mut candidate = 0u128;
    let mut extrinsic = build(candidate).await?;

    for _ in 0..CEILING_PASSES {
        let priced = estimate(rpc, &extrinsic).await?;
        if priced <= candidate {
            return Ok(extrinsic);
        }
        candidate = priced;
        extrinsic = build(candidate).await?;
    }

    Ok(extrinsic)
}

#[cfg(test)]
mod tests {
    use parity_scale_codec::Encode;
    use subxt_rpcs::RpcClient as HostRpcClient;

    use crate::runtime::statement_allowance::rpc::testing::ScriptedRpc;

    use super::*;

    fn block_on<F: Future>(future: F) -> F::Output {
        futures::executor::block_on(future)
    }

    fn scripted(responses: &[String]) -> (ScriptedRpc, RpcClient) {
        let scripted = ScriptedRpc::new(responses.iter().map(String::as_str));
        let rpc = RpcClient::new(HostRpcClient::new(scripted.clone()));
        (scripted, rpc)
    }

    /// `RuntimeDispatchInfo { weight, class, partial_fee }` as the runtime API
    /// returns it.
    fn dispatch_info(fee: u128) -> String {
        let mut encoded = Compact(1_000_000u64).encode();
        encoded.extend(Compact(4_096u64).encode());
        encoded.push(0u8); // DispatchClass::Normal
        encoded.extend(fee.encode());
        format!("\"0x{}\"", hex::encode(encoded))
    }

    #[test]
    fn a_dispatch_info_is_decoded_field_by_field() {
        let encoded = {
            let mut encoded = Compact(7u64).encode();
            encoded.extend(Compact(8u64).encode());
            encoded.push(1u8);
            encoded.extend(9_999u128.encode());
            encoded
        };

        assert_eq!(decode_partial_fee(&encoded).expect("decodes"), 9_999);
    }

    #[test]
    fn a_truncated_dispatch_info_is_refused_rather_than_priced() {
        // Reading a short reply as a small fee would set a ceiling the runtime
        // then exceeds, and the dispatch fails after the token is spent.
        let refused =
            decode_partial_fee(&[0x04, 0x08]).expect_err("a reply this short cannot carry a fee");

        assert!(refused.to_string().contains("RuntimeDispatchInfo"));
    }

    #[test]
    fn an_estimate_prices_the_bytes_it_was_given() {
        let (scripted, rpc) = scripted(&["\"0xfeed\"".to_string(), dispatch_info(1_234)]);

        let fee = block_on(estimate(&rpc, &[1, 2, 3, 4])).expect("prices");

        assert_eq!(fee, 1_234);
        let (method, params) = scripted.calls()[1].clone();
        assert_eq!(method, "state_call");
        assert!(params.contains(QUERY_INFO));
        // The extrinsic, then its length as a little-endian u32.
        assert!(
            params.contains("0x0102030404000000"),
            "the API's (uxt, len) argument pair: {params}"
        );
    }

    #[test]
    fn a_ceiling_that_already_covers_the_fee_settles_on_the_first_pass() {
        let (scripted, rpc) = scripted(&["\"0xfeed\"".to_string(), dispatch_info(0)]);

        let extrinsic = block_on(ceiling(&rpc, |max_fee| async move {
            assert_eq!(max_fee, 0, "the first pass prices a zero ceiling");
            Ok(vec![9u8])
        }))
        .expect("settles");

        assert_eq!(extrinsic, vec![9u8]);
        assert_eq!(scripted.calls().len(), 2, "one price, no rebuild");
    }

    #[test]
    fn a_ceiling_is_raised_to_the_price_of_its_own_bytes() {
        let (_scripted, rpc) = scripted(&[
            "\"0xfeed\"".to_string(),
            dispatch_info(500),
            "\"0xfeed\"".to_string(),
            dispatch_info(500),
        ]);
        let seen = std::sync::Mutex::new(Vec::new());

        let extrinsic = block_on(ceiling(&rpc, |max_fee| {
            seen.lock().unwrap().push(max_fee);
            async move { Ok(max_fee.to_le_bytes().to_vec()) }
        }))
        .expect("settles");

        assert_eq!(
            *seen.lock().unwrap(),
            vec![0, 500],
            "priced at zero, then rebuilt at the price"
        );
        assert_eq!(
            extrinsic,
            500u128.to_le_bytes().to_vec(),
            "the extrinsic returned is the one carrying the settled ceiling"
        );
    }
}
