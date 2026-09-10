package io.paritytech.polkadotapp.feature_products_api.model.signing

import io.paritytech.polkadotapp.feature_products_api.model.ProductAccountId

/**
 * Domain model representing SignerPayloadJSON from Polkadot.js.
 * Used for signing transaction requests.
 */
class SignerPayloadJson(
    val account: ProductAccountId,
    /** The checkpoint hash of the block, in hex */
    val blockHash: ByteArray,
    /** The checkpoint block number, in hex */
    val blockNumber: ByteArray,
    /** The era for this transaction, in hex */
    val era: ByteArray,
    /** The genesis hash of the chain, in hex */
    val genesisHash: ByteArray,
    /** The encoded method (with arguments) in hex */
    val method: ByteArray,
    /** The nonce for this transaction, in hex */
    val nonce: ByteArray,
    /** The current spec version for the runtime */
    val specVersion: ByteArray,
    /** The tip for this transaction, in hex */
    val tip: ByteArray,
    /** The current transaction version for the runtime */
    val transactionVersion: ByteArray,
    /** The applicable signed extensions for this runtime */
    val signedExtensions: List<String>,
    /** The version of the extrinsic we are dealing with */
    val version: Int,
    /** The id of the asset used to pay fees, in hex (optional) */
    val assetId: ByteArray?,
    /** The metadataHash for the CheckMetadataHash SignedExtension, as hex (optional) */
    val metadataHash: ByteArray?,
    /** The mode for the CheckMetadataHash SignedExtension, in hex (optional) */
    val mode: Int?,
    /** Optional flag that enables the use of the signedTransaction field */
    val withSignedTransaction: Boolean?,
)
