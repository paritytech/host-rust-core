package io.paritytech.polkadotapp.feature_upgrade_username_impl.data

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchContext
import io.paritytech.polkadotapp.feature_dotns_api.domain.DotNsTldProvider
import io.paritytech.polkadotapp.feature_dotns_api.domain.getTldRetrying
import javax.inject.Inject

class ResourcesContextProvider @Inject constructor(
    private val dotNsTldProvider: DotNsTldProvider,
) {
    suspend fun context(): BandersnatchContext {
        return BandersnatchContext.resources(dotNsTldProvider.getTldRetrying())
    }
}
