package io.paritytech.polkadotapp.feature_settings_api.domain.language

import kotlinx.coroutines.flow.Flow

/**
 * The language the app presents its interface in, as a BCP 47 language tag (e.g. "en", "es").
 * Emits the current value on subscribe and again on every change.
 */
interface AppLanguageProvider {
    val languageTag: Flow<String>
}
