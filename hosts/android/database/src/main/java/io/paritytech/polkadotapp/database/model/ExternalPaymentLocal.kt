package io.paritytech.polkadotapp.database.model

import androidx.room.Entity
import androidx.room.PrimaryKey
import java.math.BigInteger

@Entity(tableName = "external_payments")
class ExternalPaymentLocal(
    @PrimaryKey val id: String,
    val origin: String,
    val amountPlanks: BigInteger,
    val destination: ByteArray,
    val stage: Stage,
    val failureReason: String?,
    /** JSON-encoded list of voucher ring-vrf-key indices selected for offboard. */
    val selectedVoucherKeys: String?,
    val surplusPlanks: BigInteger?,
    val createdAt: Long,
    val updatedAt: Long,
) {
    enum class Stage {
        ENSURE_VOUCHERS,
        OFFBOARD_VOUCHERS,
        COMPLETED,
        PARTIALLY_COMPLETED,
        FAILED,
    }
}
