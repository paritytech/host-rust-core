package io.paritytech.polkadotapp.feature_videogame_impl.data.repositories

import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.database.dao.VideoGameConnectionAttemptDao
import io.paritytech.polkadotapp.database.model.VideoGameConnectionAttemptLocal
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.webrtc.OfferId
import javax.inject.Inject

class ConnectionAttemptTracker @Inject constructor(
    private val dao: VideoGameConnectionAttemptDao
) {
    suspend fun getLastOfferId(gameIndex: GameIndex, accountId: AccountId): OfferId? {
        return dao.get(gameIndex.value, accountId.value)?.offerId
    }

    suspend fun saveOfferId(gameIndex: GameIndex, accountId: AccountId, offerId: OfferId) {
        dao.insert(
            VideoGameConnectionAttemptLocal(
                gameIndex = gameIndex.value,
                accountId = accountId.value,
                offerId = offerId
            )
        )
    }
}
