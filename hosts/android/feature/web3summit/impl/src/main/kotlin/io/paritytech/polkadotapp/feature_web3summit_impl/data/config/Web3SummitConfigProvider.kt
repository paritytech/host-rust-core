package io.paritytech.polkadotapp.feature_web3summit_impl.data.config

import io.paritytech.polkadotapp.common.domain.model.hexToDataByteArray
import io.paritytech.polkadotapp.feature_web3summit_impl.domain.config.Web3SummitEnvironmentConfig
import io.paritytech.polkadotapp.tools_remoteconfig_api.RemoteConfigService
import io.paritytech.polkadotapp.tools_remoteconfig_api.getSyncedJsonObject
import javax.inject.Inject

interface Web3SummitConfigProvider {
    suspend fun getConfig(): Result<Web3SummitEnvironmentConfig>
}

class RemoteConfigWeb3SummitConfigProvider @Inject constructor(
    private val remoteConfigService: RemoteConfigService,
) : Web3SummitConfigProvider {
    private companion object {
        const val CONFIG_KEY = "web3summit_config"
    }

    override suspend fun getConfig(): Result<Web3SummitEnvironmentConfig> {
        return remoteConfigService.getSyncedJsonObject<Web3SummitConfigRemote>(CONFIG_KEY)
            .mapCatching { it.toDomain() }
    }

    private fun Web3SummitConfigRemote.toDomain(): Web3SummitEnvironmentConfig {
        return Web3SummitEnvironmentConfig(
            dotNsUrl = dotNsUrl,
            contractAddress = contractAddress.hexToDataByteArray(),
        )
    }
}
