package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.list.compose.components

import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import io.paritytech.polkadotapp.design.components.icon.NovaIcon
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.ArrowRight
import io.paritytech.polkadotapp.design.components.icon.vectors.Lock
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.theme.PolkadotTheme

@Composable
internal fun FamilyItemIcon(canNavigate: Boolean) {
    if (canNavigate) {
        PolkadotSurface(
            shape = PolkadotTheme.shapes.full,
            color = Color(0x1FFFFFFF),
        ) {
            NovaIcon(
                modifier = Modifier.padding(PolkadotTheme.spacings.extraMedium),
                imageVector = NovaIcons.ArrowRight,
                tint = PolkadotTheme.colors.fg.tertiary
            )
        }
    } else {
        NovaIcon(
            modifier = Modifier.padding(PolkadotTheme.spacings.extraMedium),
            imageVector = NovaIcons.Lock,
            tint = PolkadotTheme.colors.fg.tertiary
        )
    }
}
