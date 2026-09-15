package io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.models

import androidx.compose.runtime.Immutable
import io.paritytech.polkadotapp.feature_videogame_impl.domain.notifications.GameStartAlarmOffset

@Immutable
data class AlertSettingsUiState(
    val selectedOffset: GameStartAlarmOffset
)
