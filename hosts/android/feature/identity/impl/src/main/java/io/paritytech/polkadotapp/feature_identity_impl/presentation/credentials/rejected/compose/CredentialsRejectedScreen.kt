package io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.rejected.compose

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.design.components.button.common.PolkadotButtonStyle
import io.paritytech.polkadotapp.design.components.button.default.PolkadotTextButton
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.spacer.FillerSpacer
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.rejected.CredentialsRejectedContract
import io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.rejected.compose.icons.CredentialsRejected
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun CredentialsRejectedScreen(contract: CredentialsRejectedContract) {
    CredentialsRejectedScreenInternal(
        onAction = contract::onActionClicked
    )
}

@Composable
private fun CredentialsRejectedScreenInternal(
    onAction: () -> Unit
) {
    PolkadotSurface {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(PolkadotTheme.spacings.large)
                .systemBarsPadding(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            VerticalSpacer { 76.dp }

            Image(
                imageVector = NovaIcons.CredentialsRejected,
                contentDescription = "credentials_rejected"
            )

            VerticalSpacer { extraLargeIncreased }

            NovaText(
                text = stringResource(RCommon.string.identity_credentials_rejected_title),
                style = PolkadotTheme.typography.headline.large,
                color = PolkadotTheme.colors.fg.primary,
                textAlign = TextAlign.Center
            )

            VerticalSpacer { mediumIncreased }

            NovaText(
                text = stringResource(RCommon.string.identity_credentials_rejected_description),
                style = PolkadotTheme.typography.body.large,
                color = PolkadotTheme.colors.fg.tertiary,
                textAlign = TextAlign.Center
            )

            FillerSpacer()

            PolkadotTextButton(
                modifier = Modifier.fillMaxWidth(),
                text = stringResource(RCommon.string.identity_credentials_rejected_action),
                style = PolkadotButtonStyle.primary(),
                onClick = onAction
            )
        }
    }
}

@Preview
@Composable
fun CredentialsRejectedScreenPreview() {
    PolkadotTheme {
        PolkadotSurface {
            CredentialsRejectedScreenInternal(
                onAction = {}
            )
        }
    }
}
