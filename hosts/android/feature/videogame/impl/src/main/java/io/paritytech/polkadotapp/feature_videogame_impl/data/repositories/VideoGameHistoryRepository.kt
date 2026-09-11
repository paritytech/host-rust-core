package io.paritytech.polkadotapp.feature_videogame_impl.data.repositories

import io.paritytech.polkadotapp.chains.di.RemoteSourceQualifier
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.chains.storage.source.StorageDataSource
import io.paritytech.polkadotapp.chains.storage.source.query.metadata
import io.paritytech.polkadotapp.chains.storage.source.queryCatching
import io.paritytech.polkadotapp.chains.storage.source.subscribeCatching
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_videogame_impl.data.gameHistory
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainAccountOrPerson
import io.paritytech.polkadotapp.feature_videogame_impl.data.playerAttendanceHistory
import io.paritytech.polkadotapp.feature_videogame_impl.data.videoGame
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.GameAttendance
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.HistoricalGameInfo
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import kotlin.time.Duration.Companion.seconds

interface VideoGameHistoryRepository {
    suspend fun getHistoricalGameInfos(chainId: ChainId): Result<List<HistoricalGameInfo>>

    fun attendanceHistoryFlow(chainId: ChainId, accountOrPerson: OnChainAccountOrPerson): Flow<Result<GameAttendance>>
}

fun VideoGameHistoryRepository.accountAttendanceHistoryFlow(chainId: ChainId, accountId: AccountId): Flow<Result<GameAttendance>> {
    return attendanceHistoryFlow(chainId, OnChainAccountOrPerson.Account(accountId))
}

class RealVideoGameHistoryRepository @Inject constructor(
    @RemoteSourceQualifier private val remoteStorageSource: StorageDataSource
) : VideoGameHistoryRepository {
    override suspend fun getHistoricalGameInfos(chainId: ChainId): Result<List<HistoricalGameInfo>> {
        return remoteStorageSource.queryCatching(chainId) {
            metadata.videoGame.gameHistory.entries().map { (gameIndex, gameTimestamp) ->
                HistoricalGameInfo(gameIndex, gameTimestamp.seconds)
            }
        }
    }

    override fun attendanceHistoryFlow(
        chainId: ChainId,
        accountOrPerson: OnChainAccountOrPerson
    ): Flow<Result<GameAttendance>> {
        return remoteStorageSource.subscribeCatching(chainId) {
            metadata.videoGame.playerAttendanceHistory.observe(accountOrPerson)
                .map { it.orEmpty().toSet() }
        }
    }
}
