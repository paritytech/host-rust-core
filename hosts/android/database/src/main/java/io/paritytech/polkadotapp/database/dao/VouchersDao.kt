package io.paritytech.polkadotapp.database.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import io.paritytech.polkadotapp.database.model.VoucherLocal
import io.paritytech.polkadotapp.database.model.VoucherStateLocal
import kotlinx.coroutines.flow.Flow

@Dao
abstract class VouchersDao {
    @Query("SELECT COALESCE(MAX(voucherIndex), -1) + 1 FROM vouchers WHERE type = :type")
    abstract suspend fun getNextIndexForType(type: String): Int

    @Query("""
        SELECT * FROM vouchers
        WHERE type = :type AND voucherIndex = (
            SELECT MAX(voucherIndex)
            FROM vouchers
            WHERE type = :type
        )
    """)
    abstract suspend fun getWithMaxIndexByType(type: String): VoucherLocal?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    abstract suspend fun insertVoucher(voucher: VoucherLocal): Long

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    abstract suspend fun insertVouchers(vouchers: List<VoucherLocal>)

    @Query("SELECT * FROM vouchers")
    abstract fun allVouchersFlow(): Flow<List<VoucherLocal>>

    @Query("SELECT * FROM vouchers")
    abstract suspend fun getAllVouchers(): List<VoucherLocal>

    @Query("SELECT * FROM vouchers WHERE type = :type")
    abstract suspend fun getVouchersByType(type: String): List<VoucherLocal>

    @Query("SELECT * FROM vouchers WHERE state = :state")
    abstract suspend fun getVouchersByState(state: VoucherStateLocal): List<VoucherLocal>

    @Query("DELETE FROM vouchers WHERE voucherIndex = :index AND type = :type")
    abstract suspend fun removeVoucher(index: Int, type: String)

    @Query("DELETE FROM vouchers")
    abstract suspend fun removeAllVouchers()

    @Query("UPDATE vouchers SET state = :state WHERE voucherIndex = :index AND type = :type")
    abstract suspend fun updateVoucherState(index: Int, type: String, state: VoucherStateLocal): Int

    @Query("SELECT EXISTS(SELECT * FROM vouchers WHERE type = :type AND voucherIndex = :index)")
    abstract suspend fun isVoucherExists(index: Int, type: String): Boolean

    @Query("SELECT * FROM vouchers WHERE voucherIndex = :index AND type = :type LIMIT 1")
    abstract suspend fun getVoucher(index: Int, type: String): VoucherLocal?

    @Transaction
    open suspend fun withTransaction(action: suspend () -> Unit) {
        return action()
    }
}
