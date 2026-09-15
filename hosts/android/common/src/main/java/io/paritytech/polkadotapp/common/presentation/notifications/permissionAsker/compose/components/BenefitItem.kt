package io.paritytech.polkadotapp.common.presentation.notifications.permissionAsker.compose.components

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.design.components.icon.NovaIcon
import io.paritytech.polkadotapp.design.components.spacer.HorizontalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme

@Composable
fun BenefitItem(
    modifier: Modifier = Modifier,
    icon: ImageVector,
    description: String
) {
    PolkadotSurface(
        modifier = modifier,
        shape = PolkadotTheme.shapes.full,
        color = PolkadotTheme.colors.bg.surface.container,
    ) {
        Row(
            modifier = Modifier.padding(all = PolkadotTheme.spacings.small),
            verticalAlignment = Alignment.CenterVertically
        ) {
            PolkadotSurface(
                shape = PolkadotTheme.shapes.full,
                color = PolkadotTheme.colors.bg.surface.nested,
                contentAlignment = Alignment.Center
            ) {
                NovaIcon(
                    modifier = Modifier
                        .padding(10.dp)
                        .size(28.dp),
                    imageVector = icon,
                    tint = PolkadotTheme.colors.fg.primary
                )
            }

            HorizontalSpacer { extraMedium }

            NovaText(
                text = description,
                color = PolkadotTheme.colors.fg.primary,
                style = PolkadotTheme.typography.title.medium
            )
        }
    }
}
