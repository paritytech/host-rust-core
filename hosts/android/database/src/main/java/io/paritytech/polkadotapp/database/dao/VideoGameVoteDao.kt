package io.paritytech.polkadotapp.database.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import io.paritytech.polkadotapp.database.model.VideoGameVoteLocal

@Dao
interface VideoGameVoteDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertVote(vote: VideoGameVoteLocal): Long

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertVotes(votes: List<VideoGameVoteLocal>)

    @Query("DELETE FROM video_game_votes")
    suspend fun removeAllVotes()

    @Query("SELECT * FROM video_game_votes WHERE accountId = :accountId")
    suspend fun getVotesFor(accountId: ByteArray): List<VideoGameVoteLocal>

    @Query("SELECT * FROM video_game_votes")
    suspend fun getAllVotes(): List<VideoGameVoteLocal>

    @Query("SELECT * FROM video_game_votes WHERE gameIndex = :index")
    suspend fun getVotesForGame(index: Int): List<VideoGameVoteLocal>
}
