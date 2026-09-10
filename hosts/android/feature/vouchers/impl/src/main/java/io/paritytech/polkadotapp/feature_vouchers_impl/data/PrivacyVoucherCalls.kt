package io.paritytech.polkadotapp.feature_vouchers_impl.data

import io.novasama.substrate_sdk_android.runtime.extrinsic.builder.ExtrinsicBuilder
import io.novasama.substrate_sdk_android.runtime.extrinsic.call
import io.paritytech.polkadotapp.chains.network.binding.Balance
import io.paritytech.polkadotapp.chains.util.Modules
import io.paritytech.polkadotapp.common.domain.model.AccountId
import java.math.BigInteger

@JvmInline
value class PrivacyVoucherCalls(val extrinsicBuilder: ExtrinsicBuilder)

val ExtrinsicBuilder.privacyVoucher: PrivacyVoucherCalls
    get() = PrivacyVoucherCalls(this)

fun PrivacyVoucherCalls.claimVoucherIntoDestination(
    proof: ByteArray,
    dest: AccountId,
    voucherValue: Balance,
    ringIndex: BigInteger
) {
    extrinsicBuilder.call(
        moduleName = Modules.PRIVACY_VOUCHER,
        callName = "claim_voucher_into_destination",
        arguments = mapOf(
            "proof" to proof,
            "dest" to dest.value,
            "voucher_value" to voucherValue.value,
            "ring_index" to ringIndex
        )
    )
}
