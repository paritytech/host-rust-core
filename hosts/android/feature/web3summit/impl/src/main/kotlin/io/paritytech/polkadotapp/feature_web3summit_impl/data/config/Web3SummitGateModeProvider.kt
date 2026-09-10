package io.paritytech.polkadotapp.feature_web3summit_impl.data.config

import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.tools_remoteconfig_api.RemoteConfigService
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject

class Web3SummitGateModeProvider @Inject constructor(
    private val remoteConfig: RemoteConfigService,
) {
    suspend fun current(): Web3SummitGateMode = remoteConfig.getSyncedString(KEY)
        .map(::parse)
        .logFailure("Failed to get Web3SummitGateMode")
        .getOrDefault(DEFAULT)

    fun observe(): Flow<Web3SummitGateMode> = remoteConfig.observeString(KEY).map(::parse)

    private fun parse(raw: String): Web3SummitGateMode =
        runCatching { Web3SummitGateMode.valueOf(raw) }.getOrDefault(DEFAULT)

    companion object {
        private const val KEY = "w3s_gate_mode"
        private val DEFAULT = Web3SummitGateMode.VERIFICATION_ENABLED
    }
}
