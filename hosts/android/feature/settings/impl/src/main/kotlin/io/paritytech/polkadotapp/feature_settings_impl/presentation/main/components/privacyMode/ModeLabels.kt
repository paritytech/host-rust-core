package io.paritytech.polkadotapp.feature_settings_impl.presentation.main.components.privacyMode

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import kotlinx.collections.immutable.ImmutableList

@Composable
internal fun ModeLabels(appearances: ImmutableList<ModeAppearance>, highlightedIndex: Int) {
    Row(modifier = Modifier.fillMaxWidth()) {
        appearances.forEachIndexed { index, appearance ->
            NovaText(
                modifier = Modifier.weight(1f),
                text = appearance.label,
                style = PolkadotTheme.typography.title.tiny,
                color = if (index == highlightedIndex) {
                    PolkadotTheme.colors.fg.primary
                } else {
                    PolkadotTheme.colors.fg.secondary
                },
                // The outer labels hug the ends of the track the way their circles do; only the middle one
                // is free to centre.
                textAlign = when (index) {
                    0 -> TextAlign.Start
                    appearances.lastIndex -> TextAlign.End
                    else -> TextAlign.Center
                },
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}
