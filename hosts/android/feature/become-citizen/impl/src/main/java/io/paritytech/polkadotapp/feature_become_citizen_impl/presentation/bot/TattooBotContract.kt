package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.bot

import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.bot.model.TattooBotUiState
import io.paritytech.polkadotapp.feature_people_api.presentation.mixin.DimSwitchMixin
import kotlinx.coroutines.flow.StateFlow

interface TattooBotContract {
    val state: StateFlow<TattooBotUiState>
    val dimSwitchMixin: DimSwitchMixin

    fun proceedToTattooSelection()
    fun provideVideoEvidence()
    fun providePhotoEvidence()
    fun onUpgradeUsernameClick()
    fun onNavigationToDim2Click()
    fun onNavigationToMobRuleClick()
}
