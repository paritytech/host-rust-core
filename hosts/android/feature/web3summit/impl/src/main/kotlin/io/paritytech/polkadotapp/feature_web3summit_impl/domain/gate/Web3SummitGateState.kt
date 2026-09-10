package io.paritytech.polkadotapp.feature_web3summit_impl.domain.gate

import io.paritytech.polkadotapp.feature_web3summit_impl.data.config.Web3SummitGateMode
import io.paritytech.polkadotapp.feature_web3summit_impl.data.config.Web3SummitGateModeProvider
import io.paritytech.polkadotapp.feature_web3summit_impl.data.storage.PreferencesLightPersonhoodEstablishedStorage
import io.paritytech.polkadotapp.feature_web3summit_impl.data.storage.PreferencesWeb3SummitVerifiedStorage
import javax.inject.Inject

sealed interface Web3SummitDestination {
    object Main : Web3SummitDestination
    object Spa : Web3SummitDestination
    object Ended : Web3SummitDestination
}

class Web3SummitGateState @Inject constructor(
    private val modeProvider: Web3SummitGateModeProvider,
    private val verified: PreferencesWeb3SummitVerifiedStorage,
    private val lightPersonhood: PreferencesLightPersonhoodEstablishedStorage,
) {
    suspend fun decideDestination(): Web3SummitDestination {
        val mode = modeProvider.current()
        return when {
            mode == Web3SummitGateMode.W3S_ENDED -> Web3SummitDestination.Ended
            mode == Web3SummitGateMode.VERIFICATION_DISABLED -> Web3SummitDestination.Main
            !lightPersonhood.isEstablished() || !verified.isVerified() -> Web3SummitDestination.Spa
            else -> Web3SummitDestination.Main
        }
    }

    suspend fun isSkippable(): Boolean = modeProvider.current() == Web3SummitGateMode.VERIFICATION_ENABLED_SKIPPABLE
}
