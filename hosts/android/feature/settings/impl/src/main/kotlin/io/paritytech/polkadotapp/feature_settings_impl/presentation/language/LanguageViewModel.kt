package io.paritytech.polkadotapp.feature_settings_impl.presentation.language

import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.feature_settings_impl.SettingsRouter
import io.paritytech.polkadotapp.feature_settings_impl.data.repository.LanguageRepository
import io.paritytech.polkadotapp.feature_settings_impl.domain.model.Language
import io.paritytech.polkadotapp.feature_settings_impl.presentation.language.models.LanguageState
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject
@HiltViewModel
class LanguageViewModel @Inject constructor(
    private val router: SettingsRouter,
    private val repository: LanguageRepository
) : BaseViewModel(), LanguageContract {
    companion object {
        private const val STOP_TIMEOUT_MILLIS = 5000L
    }

    override val state: StateFlow<LanguageState> = repository.selectedLanguage
        .map { selected ->
            LanguageState(
                selectedLanguage = selected,
                availableLanguages = Language.entries
            )
        }
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(STOP_TIMEOUT_MILLIS),
            initialValue = LanguageState()
        )

    override fun onLanguageSelected(language: Language) {
        if (language == state.value.selectedLanguage) return
        viewModelScope.launch {
            repository.setLanguage(language)

            val appLocale = LocaleListCompat.forLanguageTags(language.code)
            delay(200)
            AppCompatDelegate.setApplicationLocales(appLocale)
            router.back()
        }
    }

    override fun onBackClick() {
        router.back()
    }
}
