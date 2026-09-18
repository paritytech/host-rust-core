package io.paritytech.polkadotapp.database.model

import androidx.room.Embedded
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import io.paritytech.polkadotapp.database.model.DurableTxLocal.Companion.TABLE_NAME

/**
 * One submitted transaction the durability engine has taken responsibility for.
 *
 * Domain-neutral by construction: the bytes' hash, the window they are valid in, and what the ledger has
 * concluded. Whatever a domain locks for a transaction lives in that domain's own tables, keyed on [id] and
 * written inside the same transaction as this row.
 *
 * Signed bytes are deliberately not persisted here — nothing in this table can be replayed onto the chain.
 * Rows are never deleted.
 */
@Entity(
    tableName = TABLE_NAME,
    indices = [
        Index(value = ["domainId", "operationGroupId"]),
        Index(value = ["domainId", "status"]),
    ],
)
class DurableTxLocal(
    /** Registration order, and the key a domain's own rows reference. */
    @PrimaryKey(autoGenerate = true)
    val id: Long,
    val domainId: String,
    val operationGroupId: String?,
    val txHash: String,
    @Embedded(prefix = "checkpoint") val checkpoint: BlockRefLocal,
    val mortalityBlocks: Long,
    @Embedded(prefix = "successDetected") val successDetectedAt: BlockRefLocal?,
    val status: Status,
) {
    enum class Status { PENDING, PENDING_SUCCESS, FINALIZED_SUCCESS, FAILURE }

    companion object {
        const val TABLE_NAME = "durable_tx"

        const val UNSAVED_ID = 0L
    }
}
