package io.paritytech.polkadotapp.feature_web3summit_impl.domain.warmUp

import io.paritytech.polkadotapp.common.utils.flatMap
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.feature_dotns_api.domain.DotNsResolver
import io.paritytech.polkadotapp.feature_web3summit_impl.data.config.Web3SummitConfigProvider
import javax.inject.Inject

interface Web3SummitWarmUpService {
    suspend fun warmUpWeb3SummitContent()
}

class RealWeb3SummitWarmUpService @Inject constructor(
    private val configProvider: Web3SummitConfigProvider,
    private val dotNsResolver: DotNsResolver,
) : Web3SummitWarmUpService {
    override suspend fun warmUpWeb3SummitContent() {
        configProvider.getConfig()
            .flatMap { config -> dotNsResolver.resolveToLocalUri(config.productId.value) }
            .logFailure("Failed to warm up web3summit content")
    }
}
