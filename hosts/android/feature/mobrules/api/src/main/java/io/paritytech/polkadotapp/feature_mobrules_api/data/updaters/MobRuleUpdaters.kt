package io.paritytech.polkadotapp.feature_mobrules_api.data.updaters

import io.paritytech.polkadotapp.chains.network.updaters.Updater
import javax.inject.Inject

class MobRuleUpdaters @Inject constructor(
    val peopleChainUpdaters: Set<@JvmSuppressWildcards Updater<*>>
)
