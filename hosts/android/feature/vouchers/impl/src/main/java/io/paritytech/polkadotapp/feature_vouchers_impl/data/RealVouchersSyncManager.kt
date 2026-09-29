package io.paritytech.polkadotapp.feature_vouchers_impl.data

import io.paritytech.polkadotapp.common.presentation.resources.ContextManager
import io.paritytech.polkadotapp.feature_vouchers_api.data.VouchersSyncManager

class RealVouchersSyncManager(
    private val contextManager: ContextManager
) : VouchersSyncManager {
    override fun scheduleVoucherSync() {
        VouchersSyncWorker.startVouchersSyncWorker(contextManager.applicationContext)
    }
}
