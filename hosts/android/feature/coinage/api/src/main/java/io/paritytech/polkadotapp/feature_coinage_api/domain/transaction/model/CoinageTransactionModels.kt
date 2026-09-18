package io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model

import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.CoinageKeyIndex
import io.paritytech.polkadotapp.feature_transactions.api.data.EnrichedSendableExtrinsic
import io.paritytech.polkadotapp.feature_transactions.api.domain.durable.DurableTxId
import io.paritytech.polkadotapp.feature_transactions.api.domain.durable.DurableTxStatus
import io.paritytech.polkadotapp.feature_transactions.api.domain.durable.OperationGroupId

/**
 * Coinage's transactions are rows of the shared durability ledger, so these name the engine's types rather
 * than parallel ones. Callers keep the coinage-flavoured spelling; there is one set of values underneath.
 *
 * The status has no alias: Kotlin cannot import an enum entry through one, and callers import these by
 * name, so they name [DurableTxStatus] directly.
 */
typealias CoinageTransactionId = DurableTxId

typealias CoinageOperationGroupId = OperationGroupId

typealias CheckpointBlock = io.paritytech.polkadotapp.feature_transactions.api.domain.durable.CheckpointBlock

/** One signed transaction with the assets it consumes and mints. */
data class CoinageTransactionRequest(
    val extrinsic: EnrichedSendableExtrinsic,
    val inputs: List<CoinageInput>,
    val outputs: List<OwnAsset>,
)

sealed interface CoinageInput {
    sealed interface Coin : CoinageInput {
        data class Own(val derivationIndex: CoinageKeyIndex) : Coin

        /** A coin whose key a peer sent us: never a local asset, only an input of the claim. */
        data class Received(val publicKey: DataByteArray) : Coin
    }

    data class Voucher(val ringVrfIndex: CoinageKeyIndex) : CoinageInput
}

sealed interface OwnAsset {
    data class Coin(val derivationIndex: CoinageKeyIndex) : OwnAsset

    data class Voucher(val ringVrfIndex: CoinageKeyIndex) : OwnAsset
}

data class CoinageTransactionState(
    val id: CoinageTransactionId,
    val status: DurableTxStatus,
    val inputs: List<CoinageInput>,
    val outputs: List<OwnAsset>,
)

/**
 * What the ledger knows about one asset: which transaction mints it, which spends it, and whether its key
 * has left the device.
 *
 * The two statuses disambiguate on-chain absence, which is otherwise three different things. An absent asset
 * is unminted-yet, reverted, or consumed depending on [minterStatus]; and [consumerStatus] is what tells a
 * minted-and-unspent coin apart from one a finalized transaction already spent, since both read absent-free
 * of any lock. Either is null when no local transaction plays that role.
 */
data class CoinageAssetState(
    val handedOff: Boolean,
    val minterStatus: DurableTxStatus?,
    val consumerStatus: DurableTxStatus?,
) {
    /** An input of a transaction that has not resolved: unavailable, but not gone. */
    val isInUse: Boolean get() = consumerStatus?.isLive == true

    /** Gone for good — a finalized transaction spent it. */
    val isConsumed: Boolean get() = consumerStatus == DurableTxStatus.FINALIZED_SUCCESS

    /** Neither locked nor spent, so it may be offered for selection subject to on-chain checks. */
    val isFree: Boolean get() = !handedOff && !isInUse && !isConsumed

    companion object {
        val UNTRACKED = CoinageAssetState(handedOff = false, minterStatus = null, consumerStatus = null)
    }
}
