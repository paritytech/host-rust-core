package io.paritytech.polkadotapp.feature_settings_impl.data.repository

import io.paritytech.polkadotapp.feature_settings_impl.data.storage.LanguageStorage
import io.paritytech.polkadotapp.feature_settings_impl.domain.model.Language
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject

class RealLanguageRepository @Inject constructor(
    private val languageStorage: LanguageStorage
) : LanguageRepository {
    override val selectedLanguage: Flow<Language> =
        languageStorage.valueFlow()
            .map { it ?: Language.DEFAULT }

    override suspend fun setLanguage(language: Language) {
        languageStorage.saveValue(language)
    }

    override suspend fun getLanguage(): Language {
        return languageStorage.getValue() ?: Language.DEFAULT
    }
}
