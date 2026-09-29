package io.paritytech.polkadotapp.feature_mobrules_impl.data.credits

import io.paritytech.polkadotapp.common.presentation.resources.ContextManager
import io.paritytech.polkadotapp.feature_mobrules_api.data.credits.MobRuleCreditsSyncManager
import javax.inject.Inject

class RealMobRuleCreditsSyncManager @Inject constructor(
    private val contextManager: ContextManager
) : MobRuleCreditsSyncManager {
    override fun scheduleCreditsSync() {
        MobRuleCreditsSyncWorker.startMobRuleRewardsSyncWorker(contextManager.applicationContext)
    }
}
