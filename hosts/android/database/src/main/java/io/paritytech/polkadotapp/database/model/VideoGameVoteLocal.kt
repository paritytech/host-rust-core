package io.paritytech.polkadotapp.database.model

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(
    tableName = "video_game_votes"
)
class VideoGameVoteLocal(
    val accountId: ByteArray,
    val roundIndex: Int,
    val playerIndex: Int,
    val vote: VoteLocal,
    val gameIndex: Int
) {
    @PrimaryKey(autoGenerate = true)
    var id: Long = 0

    enum class VoteLocal {
        PERSON,
        NON_PERSON,
        NOT_PARTICIPATED
    }
}
