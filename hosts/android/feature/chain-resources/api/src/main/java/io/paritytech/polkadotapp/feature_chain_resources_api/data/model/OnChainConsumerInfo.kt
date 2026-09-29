package io.paritytech.polkadotapp.feature_chain_resources_api.data.model

import androidx.annotation.Keep
import io.paritytech.polkadotapp.common.utils.scale.AccountEcdhKeyScale
import kotlinx.serialization.Serializable

@Keep
@Serializable
class OnChainConsumerInfo(
    val identifierKey: AccountEcdhKeyScale,
    val fullUsername: String?,
    val liteUsername: String
)
