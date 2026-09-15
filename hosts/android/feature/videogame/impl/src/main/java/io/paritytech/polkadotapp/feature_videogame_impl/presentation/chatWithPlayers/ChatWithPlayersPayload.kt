package io.paritytech.polkadotapp.feature_videogame_impl.presentation.chatWithPlayers

import android.os.Parcelable
import kotlinx.parcelize.Parcelize

@Parcelize
class ChatWithPlayersPayload(
    val gameIndex: Int
) : Parcelable
