package io.paritytech.polkadotapp.feature_vouchers_api.domain

interface VouchersRestoreUseCase {
    suspend operator fun invoke(): Result<Unit>
}
