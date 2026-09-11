package io.paritytech.polkadotapp.database.model

import androidx.room.Entity

@Entity(
    tableName = "video_game_connection_attempts",
    primaryKeys = ["gameIndex", "accountId"]
)
class VideoGameConnectionAttemptLocal(
    val gameIndex: Int,
    val accountId: ByteArray,
    val offerId: String
)
