package io.paritytech.polkadotapp.database.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import io.paritytech.polkadotapp.common.domain.model.Timestamp
import io.paritytech.polkadotapp.database.model.GamePlayersLocal
import kotlinx.coroutines.flow.Flow

@Dao
interface GamePlayersDao {
    @Query("SELECT * FROM game_players WHERE gameIndex = :gameIndex")
    suspend fun getPlayersByGame(gameIndex: Int): List<GamePlayersLocal>

    @Query("SELECT * FROM game_players WHERE gameIndex = :gameIndex")
    fun subscribePlayersByGame(gameIndex: Int): Flow<List<GamePlayersLocal>>

    @Query("SELECT * FROM game_players WHERE accountId = :accountId")
    suspend fun getGamesByPlayer(accountId: ByteArray): List<GamePlayersLocal>

    @Query("SELECT gameTimestamp FROM game_players WHERE accountId = :accountId ORDER BY gameTimestamp DESC LIMIT 1")
    suspend fun getLatestGameTimestampForPlayer(accountId: ByteArray): Timestamp?

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insert(entry: GamePlayersLocal)

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertAll(entries: List<GamePlayersLocal>)

    @Query("DELETE FROM game_players WHERE gameIndex = :gameIndex")
    suspend fun deleteByGame(gameIndex: Int)
}
