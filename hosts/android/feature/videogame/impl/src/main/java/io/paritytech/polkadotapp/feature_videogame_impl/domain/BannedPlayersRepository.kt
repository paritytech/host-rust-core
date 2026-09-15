package io.paritytech.polkadotapp.feature_videogame_impl.domain

import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.domain.model.intoAccountId
import io.paritytech.polkadotapp.database.dao.VideoGameBannedPlayerDao
import io.paritytech.polkadotapp.database.model.VideoGameBannedPlayerLocal
import kotlinx.collections.immutable.ImmutableSet
import kotlinx.collections.immutable.toPersistentSet
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class BannedPlayersRepository @Inject constructor(
    private val videoGameBannedPlayerDao: VideoGameBannedPlayerDao
) {
    fun subscribeBannedPlayers(): Flow<ImmutableSet<AccountId>> =
        videoGameBannedPlayerDao.observeAll()
            .map { list -> list.map { it.accountId.intoAccountId() }.toPersistentSet() }

    suspend fun ban(accountId: AccountId) {
        videoGameBannedPlayerDao.insert(VideoGameBannedPlayerLocal(accountId.value))
    }

    suspend fun unban(accountId: AccountId) {
        videoGameBannedPlayerDao.delete(accountId.value)
    }
}
