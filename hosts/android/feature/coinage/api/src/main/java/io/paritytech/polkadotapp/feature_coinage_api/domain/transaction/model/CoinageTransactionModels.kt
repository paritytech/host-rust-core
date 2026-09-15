package io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model

import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.DerivationIndex
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.RingVrfIndex
import io.paritytech.polkadotapp.feature_transactions.api.data.EnrichedSendableExtrinsic
import java.util.UUID

@JvmInline
value class CoinageTransactionId(val value: Long)

/** Caller-chosen and opaque, so a group can be found again without storing the id anywhere. */
@JvmInline
value class CoinageOperationGroupId(val value: String) {
    companion object {
        /** For an operation with no identity of its own to derive one from. */
        fun generateNew() = CoinageOperationGroupId(UUID.randomUUID().toString())
    }
}

/** One signed transaction with the assets it consumes and mints. */
data class CoinageTransactionRequest(
    val extrinsic: EnrichedSendableExtrinsic,
    val inputs: List<CoinageInput>,
    val outputs: List<OwnAsset>,
)

sealed interface CoinageInput {
    sealed interface Coin : CoinageInput {
        data class Own(val derivationIndex: DerivationIndex) : Coin

        /** A coin whose key a peer sent us: never a local asset, only an input of the claim. */
        data class Received(val publicKey: DataByteArray) : Coin
    }

    data class Voucher(val ringVrfIndex: RingVrfIndex) : CoinageInput
}

sealed interface OwnAsset {
    data class Coin(val derivationIndex: DerivationIndex) : OwnAsset

    data class Voucher(val ringVrfIndex: RingVrfIndex) : OwnAsset
}

enum class CoinageTransactionStatus {
    PENDING,
    PENDING_SUCCESS,

    /** Terminal: executed successfully in a finalized block. */
    FINALIZED_SUCCESS,

    /** Terminal: proven not to have executed, and unable to. */
    FAILURE,
    ;

    /** Live transactions hold their inputs locked. */
    val isLive: Boolean get() = this == PENDING || this == PENDING_SUCCESS

    /**
     * Executed in a block, finalized or not.
     *
     * The threshold to read on-chain presence against: a coin is only absent-because-consumed if whatever
     * minted it actually ran, and asking for finality there while presence is read at the best head reports
     * a coin that plainly existed a moment ago as one that may never have.
     */
    val isArrived: Boolean get() = this == PENDING_SUCCESS || this == FINALIZED_SUCCESS

    /**
     * Whether there's a way for this transaction to be completed (already or in the future)
     * The only transaction that cannot provably complete is the one marked as terminal FAILURE
     */
    val canArrive: Boolean get() = this != FAILURE
}

data class CoinageTransactionState(
    val id: CoinageTransactionId,
    val status: CoinageTransactionStatus,
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
    val minterStatus: CoinageTransactionStatus?,
    val consumerStatus: CoinageTransactionStatus?,
) {
    /** An input of a transaction that has not resolved: unavailable, but not gone. */
    val isInUse: Boolean get() = consumerStatus?.isLive == true

    /** Gone for good — a finalized transaction spent it. */
    val isConsumed: Boolean get() = consumerStatus == CoinageTransactionStatus.FINALIZED_SUCCESS

    /** Neither locked nor spent, so it may be offered for selection subject to on-chain checks. */
    val isFree: Boolean get() = !handedOff && !isInUse && !isConsumed

    companion object {
        val UNTRACKED = CoinageAssetState(handedOff = false, minterStatus = null, consumerStatus = null)
    }
}

/** The finalized block a transaction's mortality is anchored to. */
data class CheckpointBlock(
    val blockNumber: Long,
    val blockHash: String,
)
