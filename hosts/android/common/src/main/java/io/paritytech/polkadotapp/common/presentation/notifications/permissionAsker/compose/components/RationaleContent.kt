package io.paritytech.polkadotapp.common.presentation.notifications.permissionAsker.compose.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import io.paritytech.polkadotapp.design.components.button.common.PolkadotButtonStyle
import io.paritytech.polkadotapp.design.components.button.default.PolkadotTextButton
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun RationalContent(
    title: String,
    message: String,
    onEnable: () -> Unit,
    onCancel: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(all = PolkadotTheme.spacings.mediumIncreased),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        VerticalSpacer { small }

        NovaText(
            text = title,
            style = PolkadotTheme.typography.headline.small,
            color = PolkadotTheme.colors.fg.primary,
            textAlign = TextAlign.Start
        )

        VerticalSpacer { small }

        NovaText(
            text = message,
            style = PolkadotTheme.typography.body.large,
            color = PolkadotTheme.colors.fg.secondary,
        )

        VerticalSpacer { extraLarge }

        PolkadotTextButton(
            modifier = Modifier.fillMaxWidth(),
            text = stringResource(RCommon.string.notification_permission_request_ok_button),
            style = PolkadotButtonStyle.primary(),
            onClick = onEnable
        )

        VerticalSpacer { small }

        PolkadotTextButton(
            modifier = Modifier.fillMaxWidth(),
            text = stringResource(RCommon.string.notification_permission_request_nah_button),
            style = PolkadotButtonStyle.destructive(),
            onClick = onCancel
        )
    }
}
