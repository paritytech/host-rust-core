package io.paritytech.polkadotapp.feature_videogame_impl.data

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchContext
import io.paritytech.polkadotapp.feature_dotns_api.domain.DotNsTldProvider
import io.paritytech.polkadotapp.feature_dotns_api.domain.getTldRetrying
import javax.inject.Inject

class ScoreContextProvider @Inject constructor(
    private val dotNsTldProvider: DotNsTldProvider,
) {
    suspend fun context(): BandersnatchContext {
        return BandersnatchContext.score(dotNsTldProvider.getTldRetrying())
    }
}
