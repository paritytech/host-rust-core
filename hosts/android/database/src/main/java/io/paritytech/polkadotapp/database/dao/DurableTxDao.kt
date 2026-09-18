package io.paritytech.polkadotapp.database.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import io.paritytech.polkadotapp.database.model.DurableTxLocal
import kotlinx.coroutines.flow.Flow

private const val LIVE_STATUSES = "('PENDING', 'PENDING_SUCCESS')"

@Dao
abstract class DurableTxDao {
    /**
     * Runs [action] in one database transaction.
     *
     * A domain writes its own rows from inside here, so its locks and the transaction row commit together
     * or not at all — there is never an extrinsic in flight without the record holding what it consumes.
     */
    @Transaction
    open suspend fun withTransaction(action: suspend () -> Unit) {
        return action()
    }

    /** Returns the id SQLite assigned, which is also this transaction's place in registration order. */
    @Insert(onConflict = OnConflictStrategy.ABORT)
    abstract suspend fun insert(transaction: DurableTxLocal): Long

    // ---- status ----

    @Query("SELECT status FROM durable_tx WHERE id = :id")
    abstract suspend fun getStatus(id: Long): DurableTxLocal.Status?

    @Query("SELECT status FROM durable_tx WHERE id = :id")
    abstract fun subscribeStatus(id: Long): Flow<DurableTxLocal.Status?>

    /** Returns the number of rows written: 0 means the transaction no longer reads [expected]. */
    @Query(
        """
        UPDATE durable_tx
        SET status = :status,
            successDetectedblockNumber = :successDetectedBlockNumber,
            successDetectedblockHash = :successDetectedBlockHash
        WHERE id = :id AND status = :expected
        """
    )
    abstract suspend fun compareAndSetStatus(
        id: Long,
        expected: DurableTxLocal.Status,
        status: DurableTxLocal.Status,
        successDetectedBlockNumber: Long?,
        successDetectedBlockHash: String?,
    ): Int

    // ---- reads ----

    @Query("SELECT * FROM durable_tx WHERE id = :id")
    abstract suspend fun get(id: Long): DurableTxLocal?

    @Query("SELECT * FROM durable_tx WHERE domainId = :domainId ORDER BY id ASC")
    abstract suspend fun getAll(domainId: String): List<DurableTxLocal>

    @Query("SELECT EXISTS(SELECT 1 FROM durable_tx WHERE status IN $LIVE_STATUSES)")
    abstract suspend fun hasLiveTransactions(): Boolean

    /** Only these domains need their oracle opened; the rest have nothing a pass could decide. */
    @Query("SELECT DISTINCT domainId FROM durable_tx WHERE status IN $LIVE_STATUSES")
    abstract suspend fun liveDomains(): List<String>

    @Query(
        """
        SELECT * FROM durable_tx
        WHERE domainId = :domainId AND operationGroupId = :groupId
        ORDER BY id ASC
        """
    )
    abstract suspend fun getGroup(domainId: String, groupId: String): List<DurableTxLocal>

    @Query(
        """
        SELECT * FROM durable_tx
        WHERE domainId = :domainId AND operationGroupId = :groupId
        ORDER BY id ASC
        """
    )
    abstract fun subscribeGroup(domainId: String, groupId: String): Flow<List<DurableTxLocal>>
}
