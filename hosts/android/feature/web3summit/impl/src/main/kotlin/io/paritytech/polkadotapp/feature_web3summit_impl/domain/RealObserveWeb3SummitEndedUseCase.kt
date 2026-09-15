package io.paritytech.polkadotapp.feature_web3summit_impl.domain

import io.paritytech.polkadotapp.feature_web3summit_api.domain.ObserveWeb3SummitEndedUseCase
import io.paritytech.polkadotapp.feature_web3summit_impl.data.config.Web3SummitGateMode
import io.paritytech.polkadotapp.feature_web3summit_impl.data.config.Web3SummitGateModeProvider
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject

class RealObserveWeb3SummitEndedUseCase @Inject constructor(
    private val modeProvider: Web3SummitGateModeProvider,
) : ObserveWeb3SummitEndedUseCase {
    override fun invoke(): Flow<Boolean> =
        modeProvider.observe().map { it == Web3SummitGateMode.W3S_ENDED }
}
