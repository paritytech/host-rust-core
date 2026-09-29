package io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.compose.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.design.components.spacer.HorizontalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
internal fun VideoWatchCountdown(
    modifier: Modifier = Modifier,
    secondsRemaining: Int
) {
    PolkadotSurface(
        modifier = modifier,
        shape = PolkadotTheme.shapes.full,
        color = Color(0x14FFFFFF),
        border = BorderStroke(PolkadotTheme.borders.default, PolkadotTheme.colors.stroke.primary),
    ) {
        Row(
            modifier = Modifier.padding(
                start = PolkadotTheme.spacings.large,
                end = PolkadotTheme.spacings.extraMedium,
                top = 14.dp,
                bottom = 14.dp
            ),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            NovaText(
                modifier = Modifier.weight(1f),
                text = stringResource(RCommon.string.mob_rule_evidence_watch_countdown),
                style = PolkadotTheme.typography.body.medium,
                color = PolkadotTheme.colors.fg.secondary
            )

            HorizontalSpacer { mediumIncreased }

            Box(
                modifier = Modifier
                    .background(Color(0x1FFFFFFF), PolkadotTheme.shapes.full)
                    .padding(PolkadotTheme.spacings.small),
                contentAlignment = Alignment.Center
            ) {
                NovaText(
                    text = secondsRemaining.toString(),
                    style = PolkadotTheme.typography.title.medium,
                    color = PolkadotTheme.colors.fg.primary
                )
            }
        }
    }
}
