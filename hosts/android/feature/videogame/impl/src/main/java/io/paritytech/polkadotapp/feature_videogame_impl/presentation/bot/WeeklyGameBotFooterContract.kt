package io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot

import io.paritytech.polkadotapp.feature_people_api.presentation.mixin.DimSwitchMixin
import io.paritytech.polkadotapp.feature_videogame_impl.domain.notifications.GameStartAlarmOffset
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.models.AlertSettingsUiState
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.models.FooterUiState
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.models.WeeklyGameDepositState
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.models.WeeklyGameFooterState
import kotlinx.coroutines.flow.StateFlow

interface WeeklyGameBotFooterContract {
    val depositState: StateFlow<WeeklyGameDepositState>
    val uiState: StateFlow<FooterUiState>
    val footerState: StateFlow<WeeklyGameFooterState>
    val alertSettingsState: StateFlow<AlertSettingsUiState>
    val dimSwitchMixin: DimSwitchMixin

    fun register()
    fun startGame()
    fun addToCalendar()
    fun deposit()
    fun cancelDeposit()
    fun onUpgradeUsernameClick()
    fun onAlertOffsetSelect(offset: GameStartAlarmOffset)

    fun setUpcomingWidgetVisible(visible: Boolean)
    fun setInlinePillVisible(visible: Boolean)
}
