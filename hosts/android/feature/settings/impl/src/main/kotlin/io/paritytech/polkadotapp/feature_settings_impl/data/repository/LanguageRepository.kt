package io.paritytech.polkadotapp.feature_settings_impl.data.repository

import io.paritytech.polkadotapp.feature_settings_impl.domain.model.Language
import kotlinx.coroutines.flow.Flow

interface LanguageRepository {
    val selectedLanguage: Flow<Language>
    suspend fun setLanguage(language: Language)
    suspend fun getLanguage(): Language
}
