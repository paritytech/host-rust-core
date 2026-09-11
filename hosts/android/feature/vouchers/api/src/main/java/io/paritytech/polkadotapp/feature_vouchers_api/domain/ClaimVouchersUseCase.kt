package io.paritytech.polkadotapp.feature_vouchers_api.domain

import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_vouchers_api.domain.models.Voucher

interface ClaimVouchersUseCase {
    suspend operator fun invoke(destination: AccountId, vouchers: List<Voucher>): Result<Unit>
}
