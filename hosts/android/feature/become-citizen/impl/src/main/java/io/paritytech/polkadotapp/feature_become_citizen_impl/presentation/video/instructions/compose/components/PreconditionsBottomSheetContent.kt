package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.video.instructions.compose.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.common.presentation.formatters.space.LocalInformationSizeFormatter
import io.paritytech.polkadotapp.design.components.button.common.PolkadotButtonStyle
import io.paritytech.polkadotapp.design.components.button.default.PolkadotTextButton
import io.paritytech.polkadotapp.design.components.icon.NovaIcon
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.ChargingFilled
import io.paritytech.polkadotapp.design.components.icon.vectors.WarningFilled
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.evidences.models.ProvideEvidencePrecondition
import io.paritytech.polkadotapp.feature_tokens_api.presentation.formatter.LocalTokenAmountFormatter
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun PreconditionsBottomSheetContent(
    precondition: ProvideEvidencePrecondition,
    onAccept: () -> Unit,
    onIgnore: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(
                top = PolkadotTheme.spacings.extraLarge,
                bottom = PolkadotTheme.spacings.mediumIncreased
            )
            .padding(
                horizontal = PolkadotTheme.spacings.mediumIncreased
            ),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        HeaderIcon(precondition)

        VerticalSpacer { extraLarge }

        TitleAndDescription(precondition)

        VerticalSpacer { extraLarge }

        Actions(
            precondition = precondition,
            onAccept = onAccept,
            onIgnore = onIgnore
        )
    }
}

@Composable
private fun Actions(
    precondition: ProvideEvidencePrecondition,
    onAccept: () -> Unit,
    onIgnore: () -> Unit
) {
    val buttonModifier = Modifier.fillMaxWidth()
    PolkadotTextButton(
        modifier = buttonModifier,
        text = stringResource(RCommon.string.evidence_video_precondition_accept_action),
        style = PolkadotButtonStyle.secondary(),
        onClick = onAccept
    )

    if (precondition is ProvideEvidencePrecondition.BatteryTooLow) {
        VerticalSpacer { small }

        PolkadotTextButton(
            modifier = buttonModifier,
            text = stringResource(RCommon.string.evidence_video_precondition_ignore_action),
            style = PolkadotButtonStyle.ghost(),
            onClick = onIgnore
        )
    }
}

@Composable
private fun TitleAndDescription(precondition: ProvideEvidencePrecondition) {
    val title: String
    val description: String

    when (precondition) {
        is ProvideEvidencePrecondition.BatteryTooLow -> {
            title = stringResource(RCommon.string.evidence_video_precondition_battery_title)
            description = stringResource(
                RCommon.string.evidence_video_precondition_battery_description,
                LocalTokenAmountFormatter.current.formatPercent(precondition.minimumLevel)
            )
        }

        is ProvideEvidencePrecondition.NotEnoughSpace -> {
            title = stringResource(RCommon.string.evidence_video_precondition_storage_title)
            description = stringResource(
                RCommon.string.evidence_video_precondition_storage_description,
                LocalInformationSizeFormatter.current.format(precondition.requiredSpace)
            )
        }
    }

    val textModifier = Modifier.padding(horizontal = PolkadotTheme.spacings.extraLarge)
    NovaText(
        modifier = textModifier,
        text = title,
        style = PolkadotTheme.typography.headline.large,
        color = PolkadotTheme.colors.fg.primary,
        textAlign = TextAlign.Center
    )

    VerticalSpacer { small }

    NovaText(
        modifier = textModifier,
        text = description,
        style = PolkadotTheme.typography.body.large,
        color = PolkadotTheme.colors.fg.tertiary,
        textAlign = TextAlign.Center
    )
}

@Composable
private fun HeaderIcon(precondition: ProvideEvidencePrecondition) {
    val color = Color(0xFFFFF626)

    PolkadotSurface(
        shape = PolkadotTheme.shapes.large,
        color = color.copy(alpha = 0.08f)
    ) {
        NovaIcon(
            modifier = Modifier
                .padding(PolkadotTheme.spacings.mediumIncreased)
                .size(48.dp),
            imageVector = when (precondition) {
                is ProvideEvidencePrecondition.BatteryTooLow -> NovaIcons.ChargingFilled
                is ProvideEvidencePrecondition.NotEnoughSpace -> NovaIcons.WarningFilled
            },
            tint = color
        )
    }
}
