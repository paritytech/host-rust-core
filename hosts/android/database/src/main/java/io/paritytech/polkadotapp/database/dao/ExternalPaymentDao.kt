package io.paritytech.polkadotapp.database.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import io.paritytech.polkadotapp.database.model.ExternalPaymentLocal
import kotlinx.coroutines.flow.Flow
import java.math.BigInteger

@Dao
interface ExternalPaymentDao {
    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(payment: ExternalPaymentLocal)

    @Query("SELECT * FROM external_payments WHERE id = :id")
    suspend fun getById(id: String): ExternalPaymentLocal?

    @Query("SELECT * FROM external_payments WHERE id = :id")
    fun observeById(id: String): Flow<ExternalPaymentLocal?>

    @Query(
        """
        SELECT * FROM external_payments
        WHERE stage NOT IN ('COMPLETED', 'FAILED')
        ORDER BY createdAt ASC LIMIT 1
        """
    )
    suspend fun getNextPending(): ExternalPaymentLocal?

    @Query(
        """
        UPDATE external_payments SET
            stage = :stage,
            selectedVoucherKeys = :selectedVoucherKeys,
            surplusPlanks = :surplusPlanks,
            failureReason = :failureReason,
            updatedAt = :updatedAt
        WHERE id = :id
        """
    )
    suspend fun updateStage(
        id: String,
        stage: ExternalPaymentLocal.Stage,
        selectedVoucherKeys: String?,
        surplusPlanks: BigInteger?,
        failureReason: String?,
        updatedAt: Long,
    )
}
