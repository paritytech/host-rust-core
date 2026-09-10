package io.paritytech.polkadotapp.feature_settings_impl.data.storage

import io.paritytech.polkadotapp.common.data.storage.SingleValueStorage
import io.paritytech.polkadotapp.common.data.storage.SingleValueStorageFactory
import io.paritytech.polkadotapp.common.data.storage.preferences.store.PreferencesSingleValueSerializer
import io.paritytech.polkadotapp.feature_settings_impl.domain.model.Language
import io.paritytech.polkadotapp.feature_settings_impl.domain.model.fromCode

internal typealias LanguageStorage = SingleValueStorage<Language>

private const val KEY_SELECTED_LANGUAGE = "selected_language"

internal fun SingleValueStorageFactory.createLanguageStorage(): LanguageStorage {
    return preferences(
        key = KEY_SELECTED_LANGUAGE,
        default = Language.DEFAULT,
        serializer = PreferencesSingleValueSerializer.from(
            toString = { it.code },
            fromString = { code -> Language.fromCode(code) }
        )
    )
}
