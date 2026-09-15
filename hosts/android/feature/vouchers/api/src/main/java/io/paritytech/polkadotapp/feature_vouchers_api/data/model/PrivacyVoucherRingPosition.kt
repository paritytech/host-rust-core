package io.paritytech.polkadotapp.feature_vouchers_api.data.model

import io.novasama.substrate_sdk_android.koltinx_serialization_scale.annotations.AsTuple
import io.novasama.substrate_sdk_android.koltinx_serialization_scale.serializers.BigIntegerSerializable
import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchPublicKey
import io.paritytech.polkadotapp.chains.network.binding.Balance
import io.paritytech.polkadotapp.feature_vouchers_api.domain.models.Voucher
import kotlinx.serialization.Serializable

@Serializable
@AsTuple
data class PrivacyVoucherRingPosition(
    val voucherValue: Balance,
    val ringIndex: BigIntegerSerializable
) {
    override fun toString(): String {
        return "($voucherValue, $ringIndex)"
    }
}

fun PrivacyVoucherRingPosition.toParts(): Pair<Balance, BigIntegerSerializable> {
    return voucherValue to ringIndex
}

fun Map<BandersnatchPublicKey, PrivacyVoucherRingPosition>.groupByPosition(): Map<PrivacyVoucherRingPosition, List<BandersnatchPublicKey>> {
    return entries.groupBy(
        keySelector = { it.value },
        valueTransform = { it.key }
    )
}

fun Map<BandersnatchPublicKey, PrivacyVoucherRingPosition>.groupByPosition(
    vouchersLookup: Map<BandersnatchPublicKey, Voucher>
): Map<PrivacyVoucherRingPosition, List<Voucher>> {
    return entries.groupBy(
        keySelector = { it.value },
        valueTransform = { vouchersLookup.getValue(it.key) }
    )
}
