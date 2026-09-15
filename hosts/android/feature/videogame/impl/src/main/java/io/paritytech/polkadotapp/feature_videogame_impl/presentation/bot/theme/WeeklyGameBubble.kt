package io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.theme

import androidx.compose.foundation.BorderStroke
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.feature_chats_api.presentation.model.ChatDateSeparatorStyle
import io.paritytech.polkadotapp.feature_chats_api.presentation.model.ChatMessageSurfaceStyle

internal val WeeklyGamePrizesBubble = ChatMessageSurfaceStyle(
    backgroundColor = NovaPrizesColors.chatBubbleBackground,
    border = BorderStroke(1.dp, NovaPrizesColors.chatBubbleBorder),
    textColor = NovaPrizesColors.textPrimary,
)

internal val WeeklyGamePrizesDateSeparator = ChatDateSeparatorStyle(
    backgroundColor = NovaPrizesColors.dateSeparatorBackground,
    textColor = NovaPrizesColors.dateSeparatorText,
)
