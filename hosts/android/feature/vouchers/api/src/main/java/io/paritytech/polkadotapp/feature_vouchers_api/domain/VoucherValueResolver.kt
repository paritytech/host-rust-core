package io.paritytech.polkadotapp.feature_vouchers_api.domain

import io.paritytech.polkadotapp.feature_vouchers_api.data.model.PrivacyVoucherDenominationType
import io.paritytech.polkadotapp.feature_vouchers_api.domain.models.VoucherValue

interface VoucherValueResolver {
    interface Factory {
        /**
         * Resolver that can be used to resolve voucher value in both foreground and background
         */
        val foreground: VoucherValueResolver
    }

    suspend fun resolveVoucherValue(voucherDenomination: PrivacyVoucherDenominationType): Result<VoucherValue>
}
