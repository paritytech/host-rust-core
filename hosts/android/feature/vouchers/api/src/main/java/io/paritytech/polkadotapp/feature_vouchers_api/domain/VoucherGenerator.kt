package io.paritytech.polkadotapp.feature_vouchers_api.domain

import io.paritytech.polkadotapp.feature_vouchers_api.domain.models.Voucher
import io.paritytech.polkadotapp.feature_vouchers_api.domain.models.VoucherType

interface VoucherGenerator {
    suspend fun generateVoucher(type: VoucherType): Voucher
}
