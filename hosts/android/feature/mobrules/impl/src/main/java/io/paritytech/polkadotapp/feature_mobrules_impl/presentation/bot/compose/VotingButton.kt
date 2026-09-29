package io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.compose

import androidx.annotation.StringRes
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.design.components.icon.NovaIcon
import io.paritytech.polkadotapp.design.components.spacer.HorizontalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme

@Composable
internal fun VotingButton(
    modifier: Modifier = Modifier,
    icon: ImageVector,
    @StringRes textRes: Int,
    contentColor: Color,
    onClick: () -> Unit
) {
    PolkadotSurface(
        modifier = modifier,
        shape = PolkadotTheme.shapes.full,
        color = Color(0x14FFFFFF),
        onClick = onClick
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(PolkadotTheme.spacings.small),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically
        ) {
            NovaIcon(
                modifier = Modifier.size(20.dp),
                imageVector = icon,
                tint = contentColor
            )
            HorizontalSpacer { small }
            NovaText(
                text = stringResource(textRes),
                color = contentColor,
                style = PolkadotTheme.typography.body.mediumEmphasized
            )
        }
    }
}
