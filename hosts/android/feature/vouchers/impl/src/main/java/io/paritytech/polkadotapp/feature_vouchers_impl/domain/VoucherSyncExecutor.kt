package io.paritytech.polkadotapp.feature_vouchers_impl.domain

import javax.inject.Inject

// Privacy vouchers module is deprecated and will be removed.
// VoucherSyncExecutor has been disabled as part of BackgroundChainConnection removal.

interface VoucherSyncExecutor {
    suspend fun sync(): Result<Unit>
}

// TODO: Remove entire privacy vouchers module
class NoOpVoucherSyncExecutor @Inject constructor() : VoucherSyncExecutor {
    override suspend fun sync(): Result<Unit> = Result.success(Unit)
}
