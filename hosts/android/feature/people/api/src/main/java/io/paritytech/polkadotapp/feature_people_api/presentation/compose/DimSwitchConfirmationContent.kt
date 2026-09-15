package io.paritytech.polkadotapp.feature_people_api.presentation.compose

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import io.paritytech.polkadotapp.design.components.button.common.PolkadotButtonStyle
import io.paritytech.polkadotapp.design.components.button.default.PolkadotTextButton
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme

@Composable
fun DimSwitchConfirmationContent(
    title: String,
    description: String,
    cancelText: String,
    confirmText: String,
    onConfirm: () -> Unit,
    onCancel: () -> Unit,
    inProgress: Boolean
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(PolkadotTheme.spacings.large),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        NovaText(
            text = title,
            style = PolkadotTheme.typography.headline.small,
            color = PolkadotTheme.colors.fg.primary,
            textAlign = TextAlign.Center
        )

        VerticalSpacer { small }

        NovaText(
            text = description,
            style = PolkadotTheme.typography.body.large,
            color = PolkadotTheme.colors.fg.secondary,
            textAlign = TextAlign.Center
        )

        VerticalSpacer { extraLargeIncreased }

        Row(
            horizontalArrangement = Arrangement.spacedBy(PolkadotTheme.spacings.small)
        ) {
            val modifier = Modifier.weight(1f)

            PolkadotTextButton(
                modifier = modifier,
                text = cancelText,
                style = PolkadotButtonStyle.ghost(),
                onClick = onCancel,
                enabled = inProgress.not()
            )

            PolkadotTextButton(
                modifier = modifier,
                text = confirmText,
                style = PolkadotButtonStyle.destructive(),
                onClick = onConfirm,
                loading = inProgress
            )
        }
    }
}

@Preview
@Composable
private fun DimSwitchConfirmationContentPreview() {
    PolkadotTheme {
        DimSwitchConfirmationContent(
            title = "Switch to DIM2?",
            description = "You will lose your progress in DIM1",
            cancelText = "Back",
            confirmText = "Switch",
            onConfirm = {},
            onCancel = {},
            inProgress = false
        )
    }
}
