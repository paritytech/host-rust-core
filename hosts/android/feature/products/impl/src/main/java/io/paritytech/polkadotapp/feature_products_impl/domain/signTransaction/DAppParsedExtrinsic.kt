package io.paritytech.polkadotapp.feature_products_impl.domain.signTransaction

import io.novasama.substrate_sdk_android.runtime.definitions.types.generics.Era
import io.novasama.substrate_sdk_android.runtime.definitions.types.generics.GenericCall
import io.paritytech.polkadotapp.feature_products_api.model.ProductAccountId
import java.math.BigInteger

/**
 * Represents a fully parsed extrinsic from SignerPayloadJSON.
 * Used for displaying human-readable transaction details.
 */
class DAppParsedExtrinsic(
    val account: ProductAccountId,
    val nonce: BigInteger,
    val specVersion: Int,
    val transactionVersion: Int,
    val genesisHash: ByteArray,
    val blockHash: ByteArray,
    val era: Era,
    val tip: BigInteger,
    val call: GenericCall.Instance,
    val metadataHash: ByteArray?,
    val assetId: Any?,
)
