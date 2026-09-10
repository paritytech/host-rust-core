package io.paritytech.polkadotapp.feature_settings_impl.data.repository

import io.paritytech.polkadotapp.feature_settings_api.domain.language.AppLanguageProvider
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject

class RealAppLanguageProvider @Inject constructor(
    private val languageRepository: LanguageRepository,
) : AppLanguageProvider {
    // Language.code ("en", "es") is already a valid BCP 47 language tag.
    override val languageTag: Flow<String> = languageRepository.selectedLanguage.map { it.code }
}
