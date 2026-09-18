package io.paritytech.polkadotapp.feature_transactions.api.domain.durable

import io.paritytech.polkadotapp.feature_transactions.api.domain.model.TransactionHash
import java.util.UUID

/**
 * Which consumer a transaction belongs to. One ledger serves every domain, and a recovery pass evaluates
 * each domain against its own oracle.
 */
@JvmInline
value class TxDomainId(val value: String)

@JvmInline
value class DurableTxId(val value: Long)

/** Caller-chosen and opaque, so a group can be found again without storing the id anywhere. */
@JvmInline
value class OperationGroupId(val value: String) {
    companion object {
        /** For an operation with no identity of its own to derive one from. */
        fun generateNew() = OperationGroupId(UUID.randomUUID().toString())
    }
}

/** The finalized block a transaction's mortality is anchored to. */
data class CheckpointBlock(
    val blockNumber: Long,
    val blockHash: String,
)

enum class DurableTxStatus {
    PENDING,
    PENDING_SUCCESS,

    /** Terminal: executed successfully in a finalized block. */
    FINALIZED_SUCCESS,

    /** Terminal: proven not to have executed, and unable to. */
    FAILURE,
    ;

    /** Live transactions hold whatever their domain locked for them. */
    val isLive: Boolean get() = this == PENDING || this == PENDING_SUCCESS

    /**
     * Executed in a block, finalized or not.
     *
     * The threshold to read on-chain presence against: an asset is only absent-because-consumed if whatever
     * minted it actually ran, and asking for finality there while presence is read at the best head reports
     * something that plainly existed a moment ago as something that may never have.
     */
    val isArrived: Boolean get() = this == PENDING_SUCCESS || this == FINALIZED_SUCCESS

    /**
     * Whether there is a way for this transaction to complete, already or in the future. The only one that
     * provably cannot is a terminal [FAILURE].
     */
    val canArrive: Boolean get() = this != FAILURE
}

/**
 * What the ladder is allowed to know about one transaction.
 *
 * Deliberately thin: the bytes, the window they are valid in, and what the ledger has concluded so far.
 * Anything domain-shaped reaches the ladder only through [TxCompletionOracle].
 */
data class DurableTxEntry(
    val id: DurableTxId,
    val domainId: TxDomainId,
    val groupId: OperationGroupId?,
    val txHash: TransactionHash,
    val checkpoint: CheckpointBlock,
    val mortalityBlocks: Long,
    val status: DurableTxStatus,
    val successDetectedAt: CheckpointBlock?,
) {
    /** The last block this transaction can still execute in. */
    val mortalityEnd: Long get() = checkpoint.blockNumber + mortalityBlocks
}

data class DurableTxState(
    val id: DurableTxId,
    val status: DurableTxStatus,
)

/** A status write, and the inclusion record that justifies it. */
data class Verdict(
    val status: DurableTxStatus,
    /** Null clears the record. */
    val successDetectedAt: CheckpointBlock?,
)
