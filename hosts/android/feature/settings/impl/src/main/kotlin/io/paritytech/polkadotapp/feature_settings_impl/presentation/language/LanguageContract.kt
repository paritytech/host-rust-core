package io.paritytech.polkadotapp.feature_settings_impl.presentation.language

import io.paritytech.polkadotapp.feature_settings_impl.domain.model.Language
import io.paritytech.polkadotapp.feature_settings_impl.presentation.language.models.LanguageState
import kotlinx.coroutines.flow.StateFlow

interface LanguageContract {
    val state: StateFlow<LanguageState>

    fun onLanguageSelected(language: Language)
    fun onBackClick()
}
