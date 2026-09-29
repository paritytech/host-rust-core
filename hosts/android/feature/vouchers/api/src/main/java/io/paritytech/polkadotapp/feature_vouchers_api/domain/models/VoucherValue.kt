package io.paritytech.polkadotapp.feature_vouchers_api.domain.models

import io.paritytech.polkadotapp.chains.network.binding.Balance
import io.paritytech.polkadotapp.chains.network.binding.toInt

@JvmInline
value class VoucherValue(private val value: Balance) {
    fun issuableVouchersFrom(balance: Balance): Int {
        if (value == Balance.ZERO) return 0

        return (balance / value).toInt()
    }
}
