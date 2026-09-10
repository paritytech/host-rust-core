package io.paritytech.polkadotapp.feature_settings_impl.presentation.language.compose

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.paritytech.polkadotapp.common.R
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.topbar.PolkadotTopBar
import io.paritytech.polkadotapp.design.components.topbar.TopBarTitleAlignment
import io.paritytech.polkadotapp.design.components.topbar.rememberTopBarAction
import io.paritytech.polkadotapp.feature_settings_impl.domain.model.Language
import io.paritytech.polkadotapp.feature_settings_impl.presentation.common.SettingsSelectionDivider
import io.paritytech.polkadotapp.feature_settings_impl.presentation.language.LanguageContract
import io.paritytech.polkadotapp.feature_settings_impl.presentation.language.compose.components.LanguageItem
import io.paritytech.polkadotapp.feature_settings_impl.presentation.language.models.LanguageState

@Composable
fun LanguageScreen(contract: LanguageContract) {
    val state by contract.state.collectAsStateWithLifecycle()

    LanguageScreenInternal(
        state = state,
        onLanguageSelected = contract::onLanguageSelected,
        onBackClick = contract::onBackClick
    )
}

@Composable
private fun LanguageScreenInternal(
    state: LanguageState,
    onLanguageSelected: (Language) -> Unit,
    onBackClick: () -> Unit
) {
    PolkadotSurface {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .safeDrawingPadding()
        ) {
            PolkadotTopBar(
                title = stringResource(id = R.string.settings_language),
                navigationAction = rememberTopBarAction(onBackClick),
                titleAlignment = TopBarTitleAlignment.Center,
            )

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
            ) {
                VerticalSpacer { mediumIncreased }

                state.availableLanguages.forEachIndexed { index, language ->
                    LanguageItem(
                        flag = language.flag,
                        nativeName = language.nativeName,
                        englishName = language.englishName,
                        isSelected = language == state.selectedLanguage,
                        onClick = { onLanguageSelected(language) }
                    )

                    if (index < state.availableLanguages.lastIndex) {
                        SettingsSelectionDivider()
                    }
                }
            }
        }
    }
}
