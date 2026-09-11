package io.paritytech.polkadotapp.database.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import io.paritytech.polkadotapp.database.model.VideoGameBannedPlayerLocal
import kotlinx.coroutines.flow.Flow

@Dao
interface VideoGameBannedPlayerDao {
    @Query("SELECT * FROM video_game_banned_players")
    fun observeAll(): Flow<List<VideoGameBannedPlayerLocal>>

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insert(entry: VideoGameBannedPlayerLocal)

    @Query("DELETE FROM video_game_banned_players WHERE accountId = :accountId")
    suspend fun delete(accountId: ByteArray)
}
