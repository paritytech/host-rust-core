package io.paritytech.polkadotapp.feature_settings_impl.presentation.language.compose.components

import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.Composable
import androidx.compose.ui.tooling.preview.Preview
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_settings_impl.presentation.common.SettingsSelectionItem

@Composable
fun LanguageItem(
    flag: String,
    nativeName: String,
    englishName: String,
    isSelected: Boolean,
    onClick: () -> Unit
) {
    SettingsSelectionItem(
        isSelected = isSelected,
        onClick = onClick,
        title = nativeName,
        description = englishName,
        icon = {
            NovaText(
                text = flag,
                style = PolkadotTheme.typography.body.large,
                color = PolkadotTheme.colors.fg.primary
            )
        }
    )
}

@Preview(backgroundColor = 0xff000000, showBackground = true)
@Composable
private fun LanguageItemPreview() {
    PolkadotTheme {
        Column {
            LanguageItem(
                flag = "🇺🇸",
                nativeName = "Español",
                englishName = "Spanish",
                isSelected = true,
                onClick = {}
            )

            LanguageItem(
                flag = "🇪🇸",
                nativeName = "English",
                englishName = "English",
                isSelected = false,
                onClick = {}
            )
        }
    }
}
