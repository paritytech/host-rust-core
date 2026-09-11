package io.paritytech.polkadotapp.feature_videogame_impl.data.repositories

import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.domain.model.Timestamp
import io.paritytech.polkadotapp.common.domain.model.intoAccountId
import io.paritytech.polkadotapp.database.dao.GamePlayersDao
import io.paritytech.polkadotapp.database.model.GamePlayersLocal
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject

interface GamePlayersRepository {
    suspend fun saveGamePlayers(gameIndex: GameIndex, players: List<AccountId>, gameTimestamp: Timestamp?)

    suspend fun getGamePlayers(gameIndex: GameIndex): List<AccountId>

    fun subscribeGamePlayers(gameIndex: GameIndex): Flow<List<AccountId>>

    suspend fun getGamesForPlayer(accountId: AccountId): List<GameIndex>

    suspend fun getLatestGameTimestampForPlayer(accountId: AccountId): Timestamp?
}

class RealGamePlayersRepository @Inject constructor(
    private val gamePlayersDao: GamePlayersDao
) : GamePlayersRepository {
    override suspend fun saveGamePlayers(gameIndex: GameIndex, players: List<AccountId>, gameTimestamp: Timestamp?) {
        val entries = players.map { accountId ->
            GamePlayersLocal(
                gameIndex = gameIndex.value,
                accountId = accountId.value,
                gameTimestamp = gameTimestamp
            )
        }
        gamePlayersDao.insertAll(entries)
    }

    override suspend fun getGamePlayers(gameIndex: GameIndex): List<AccountId> {
        return gamePlayersDao.getPlayersByGame(gameIndex.value)
            .map { it.accountId.intoAccountId() }
    }

    override fun subscribeGamePlayers(gameIndex: GameIndex): Flow<List<AccountId>> {
        return gamePlayersDao.subscribePlayersByGame(gameIndex.value)
            .map { players -> players.map { it.accountId.intoAccountId() } }
    }

    override suspend fun getGamesForPlayer(accountId: AccountId): List<GameIndex> {
        return gamePlayersDao.getGamesByPlayer(accountId.value)
            .map { GameIndex(it.gameIndex) }
    }

    override suspend fun getLatestGameTimestampForPlayer(accountId: AccountId): Timestamp? {
        return gamePlayersDao.getLatestGameTimestampForPlayer(accountId.value)
    }
}
