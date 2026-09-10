package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.tattooDetails.compose.components

import androidx.compose.foundation.layout.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import io.paritytech.polkadotapp.design.components.button.common.PolkadotButtonStyle
import io.paritytech.polkadotapp.design.components.button.default.PolkadotTextButton
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun TattooCommitmentBottomSheetContent(
    commitInProgress: Boolean,
    onCancelAction: () -> Unit,
    onConfirmAction: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(PolkadotTheme.spacings.large)
    ) {
        NovaText(
            text = stringResource(RCommon.string.become_citizen_confirm_tattoo_title),
            style = PolkadotTheme.typography.headline.large,
            color = PolkadotTheme.colors.fg.primary
        )

        VerticalSpacer { extraMedium }

        NovaText(
            text = stringResource(RCommon.string.become_citizen_confirm_tattoo_description),
            style = PolkadotTheme.typography.body.large,
            color = PolkadotTheme.colors.fg.tertiary
        )

        VerticalSpacer { extraLarge }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(PolkadotTheme.spacings.small)
        ) {
            val weighModifier = Modifier.weight(1f)

            PolkadotTextButton(
                modifier = weighModifier,
                text = stringResource(RCommon.string.common_cancel),
                style = PolkadotButtonStyle.secondary(),
                onClick = onCancelAction,
                enabled = commitInProgress.not()
            )
            PolkadotTextButton(
                modifier = weighModifier,
                text = stringResource(RCommon.string.common_confirm),
                style = PolkadotButtonStyle.primary(),
                onClick = onConfirmAction,
                loading = commitInProgress
            )
        }
    }
}

@Preview
@Composable
private fun TattooCommitScreenPreview() {
    PolkadotTheme {
        TattooCommitmentBottomSheetContent(
            commitInProgress = false,
            onCancelAction = {},
            onConfirmAction = {}
        )
    }
}
