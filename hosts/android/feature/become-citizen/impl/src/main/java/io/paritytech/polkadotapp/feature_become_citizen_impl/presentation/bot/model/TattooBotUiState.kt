package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.bot.model

import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.bot.TattooBotState
import io.paritytech.polkadotapp.feature_upgrade_username_api.presentation.bot.UpgradeUsernameWidgetUiState

data class TattooBotUiState(
    val botState: TattooBotState = TattooBotState.INITIALIZING,
    val upgradeUsernameUiState: UpgradeUsernameWidgetUiState? = null,
    val showFaq: Boolean = false
)
