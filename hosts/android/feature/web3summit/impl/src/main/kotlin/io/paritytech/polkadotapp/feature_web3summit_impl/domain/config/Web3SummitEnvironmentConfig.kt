package io.paritytech.polkadotapp.feature_web3summit_impl.domain.config

import androidx.core.net.toUri
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_revive_api.EvmAccountId

class Web3SummitEnvironmentConfig(
    val dotNsUrl: String,
    val contractAddress: EvmAccountId,
) {
    val productId = ProductId.fromStoredValue(dotNsUrl.toUri().host ?: dotNsUrl)
}
