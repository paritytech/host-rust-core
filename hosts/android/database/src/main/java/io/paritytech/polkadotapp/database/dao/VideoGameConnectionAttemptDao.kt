package io.paritytech.polkadotapp.database.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy.Companion.REPLACE
import androidx.room.Query
import io.paritytech.polkadotapp.database.model.VideoGameConnectionAttemptLocal

@Dao
interface VideoGameConnectionAttemptDao {
    @Insert(onConflict = REPLACE)
    suspend fun insert(local: VideoGameConnectionAttemptLocal)

    @Query("SELECT * FROM video_game_connection_attempts WHERE gameIndex = :gameIndex AND accountId = :accountId")
    suspend fun get(gameIndex: Int, accountId: ByteArray): VideoGameConnectionAttemptLocal?

    @Query("SELECT EXISTS(SELECT 1 FROM video_game_connection_attempts WHERE gameIndex = :gameIndex AND accountId = :accountId)")
    suspend fun hasExistingOffer(gameIndex: Int, accountId: ByteArray): Boolean

    @Query("DELETE FROM video_game_connection_attempts WHERE gameIndex = :gameIndex AND accountId = :accountId")
    suspend fun delete(gameIndex: Int, accountId: ByteArray)
}
