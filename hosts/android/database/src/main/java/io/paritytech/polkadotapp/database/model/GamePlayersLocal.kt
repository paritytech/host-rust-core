package io.paritytech.polkadotapp.database.model

import androidx.room.Entity
import io.paritytech.polkadotapp.common.domain.model.Timestamp

@Entity(
    tableName = "game_players",
    primaryKeys = ["gameIndex", "accountId"]
)
class GamePlayersLocal(
    val gameIndex: Int,
    val accountId: ByteArray,
    val gameTimestamp: Timestamp?
)
