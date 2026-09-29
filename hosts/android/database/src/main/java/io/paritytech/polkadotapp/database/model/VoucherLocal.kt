package io.paritytech.polkadotapp.database.model

import androidx.room.Entity
import java.math.BigInteger

@Entity(
    tableName = "vouchers",
    primaryKeys = ["type", "voucherIndex"]
)
class VoucherLocal(
    val state: VoucherStateLocal,
    val type: String,
    val voucherIndex: Int,
    val value: BigInteger
)

enum class VoucherStateLocal {
    GENERATED, REGISTERED, CLAIMABLE, CLAIMED
}
