package io.paritytech.polkadotapp.database.model

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "video_game_banned_players")
class VideoGameBannedPlayerLocal(
    @PrimaryKey val accountId: ByteArray
)
