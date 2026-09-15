package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.photo.capture.compose.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import io.paritytech.polkadotapp.design.components.icon.NovaIcon
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.Scanner
import io.paritytech.polkadotapp.design.components.spacer.HorizontalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun OverlayToggleButton(
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    PolkadotSurface(
        modifier = modifier,
        shape = PolkadotTheme.shapes.full,
        color = Color(0x1FFFFFFF),
        onClick = onClick
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(PolkadotTheme.spacings.small)
        ) {
            PolkadotSurface(
                shape = PolkadotTheme.shapes.full,
                color = PolkadotTheme.colors.bg.surface.containerInverted
            ) {
                NovaIcon(
                    modifier = Modifier.padding(PolkadotTheme.spacings.small),
                    imageVector = NovaIcons.Scanner,
                    tint = PolkadotTheme.colors.fg.primaryInverted
                )
            }

            NovaText(
                text = stringResource(RCommon.string.evidence_photo_capture_toggle_overlay_button),
                style = PolkadotTheme.typography.body.small,
                color = PolkadotTheme.colors.fg.primary
            )

            HorizontalSpacer { mediumIncreased }
        }
    }
}
