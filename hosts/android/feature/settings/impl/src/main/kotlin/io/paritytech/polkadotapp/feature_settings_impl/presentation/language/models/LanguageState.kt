package io.paritytech.polkadotapp.feature_settings_impl.presentation.language.models

import androidx.compose.runtime.Immutable
import io.paritytech.polkadotapp.feature_settings_impl.domain.model.Language

@Immutable
data class LanguageState(
    val selectedLanguage: Language = Language.DEFAULT,
    val availableLanguages: List<Language> = Language.entries
)
