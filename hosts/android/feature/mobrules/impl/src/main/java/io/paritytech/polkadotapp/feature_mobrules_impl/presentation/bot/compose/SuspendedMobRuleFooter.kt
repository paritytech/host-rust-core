package io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.compose

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import io.paritytech.polkadotapp.design.components.button.common.PolkadotButtonStyle
import io.paritytech.polkadotapp.design.components.button.default.PolkadotTextButton
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
internal fun SuspendedMobRuleFooter(modifier: Modifier = Modifier, onReclaimClick: () -> Unit) {
    PolkadotSurface(
        modifier = modifier,
        shape = PolkadotTheme.shapes.large,
        color = Color.Transparent,
        border = BorderStroke(PolkadotTheme.borders.default, PolkadotTheme.colors.stroke.primary)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(PolkadotTheme.spacings.large),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            NovaText(
                text = stringResource(RCommon.string.mob_rule_peer_suspended_message),
                style = PolkadotTheme.typography.body.medium,
                color = PolkadotTheme.colors.fg.secondary,
                textAlign = TextAlign.Center
            )

            VerticalSpacer { mediumIncreased }

            PolkadotTextButton(
                modifier = Modifier.fillMaxWidth(),
                text = stringResource(RCommon.string.mob_rule_peer_suspended_reclaim),
                style = PolkadotButtonStyle.secondary(),
                onClick = onReclaimClick
            )
        }
    }
}

@Preview
@Composable
private fun SuspendedMobRuleFooterPreview() {
    PolkadotTheme {
        SuspendedMobRuleFooter(onReclaimClick = {})
    }
}
