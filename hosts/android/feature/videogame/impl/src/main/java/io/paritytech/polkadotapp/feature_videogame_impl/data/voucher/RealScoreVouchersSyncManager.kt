package io.paritytech.polkadotapp.feature_videogame_impl.data.voucher

import android.content.Context
import io.paritytech.polkadotapp.feature_videogame_api.data.voucher.ScoreVouchersSyncManager
import javax.inject.Inject

class RealScoreVouchersSyncManager @Inject constructor(
    private val appContext: Context
) : ScoreVouchersSyncManager {
    override fun scheduleSync() {
        RegisterScoreVouchersWorker.startRegisterScoreVouchersWorker(appContext)
    }
}
