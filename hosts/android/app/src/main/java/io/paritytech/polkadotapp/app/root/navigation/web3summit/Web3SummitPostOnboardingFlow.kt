package io.paritytech.polkadotapp.app.root.navigation.web3summit

import io.paritytech.polkadotapp.app.R
import io.paritytech.polkadotapp.app.root.navigation.BaseNavigator
import io.paritytech.polkadotapp.app.root.navigation.NavigationHolder
import io.paritytech.polkadotapp.feature_web3summit_api.presentation.PostOnboardingFlow
import io.paritytech.polkadotapp.feature_web3summit_impl.domain.gate.Web3SummitDestination
import io.paritytech.polkadotapp.feature_web3summit_impl.domain.gate.Web3SummitGateState
import javax.inject.Inject

class Web3SummitPostOnboardingFlow @Inject constructor(
    navigationHolder: NavigationHolder,
    private val gate: Web3SummitGateState,
) : BaseNavigator(navigationHolder), PostOnboardingFlow {
    override suspend fun openPostOnboarding() {
        val actionId = when (gate.decideDestination()) {
            Web3SummitDestination.Main -> R.id.action_global_to_main_graph
            Web3SummitDestination.Spa -> R.id.action_global_to_w3s_spa_graph
            Web3SummitDestination.Ended -> R.id.action_global_to_w3s_ended_graph
        }
        performNavigation(actionId)
    }
}
