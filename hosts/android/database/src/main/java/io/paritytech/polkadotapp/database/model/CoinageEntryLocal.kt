package io.paritytech.polkadotapp.database.model

import androidx.room.Embedded
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * One submitted coinage extrinsic. Rows are never deleted — later entries derive facts from earlier ones.
 *
 * The signed bytes are deliberately absent, so nothing here can be replayed onto the chain.
 */
@Entity(
    tableName = "coinage_entry",
    indices = [
        Index(value = ["operationGroupId"]),
        Index(value = ["status"]),
    ],
)
class CoinageEntryLocal(
    /** Also the registration order the recovery pass evaluates in. */
    @PrimaryKey(autoGenerate = true) val id: Long,
    val operationGroupId: String?,
    val txHash: String,
    @Embedded(prefix = "checkpoint") val checkpoint: BlockRefLocal,
    val mortalityBlocks: Long,
    /** Written only where success is already proven. */
    @Embedded(prefix = "successDetected") val successDetectedAt: BlockRefLocal?,
    val status: Status,
) {
    enum class Status {
        PENDING,
        PENDING_SUCCESS,
        FINALIZED_SUCCESS,
        FAILURE,
    }

    enum class AssetKind {
        COIN,
        VOUCHER,
    }

    companion object {
        /** Tells SQLite to assign the id on insert. */
        const val UNSAVED_ID = 0L
    }
}

class BlockRefLocal(
    val blockNumber: Long,
    val blockHash: String,
)
