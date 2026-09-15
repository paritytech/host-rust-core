package io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.compose.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.HorizontalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.util.fastForEachIndexed
import io.paritytech.polkadotapp.design.components.button.common.PolkadotButtonColors
import io.paritytech.polkadotapp.design.components.button.common.PolkadotButtonStyle
import io.paritytech.polkadotapp.design.components.button.default.PolkadotTextButton
import io.paritytech.polkadotapp.design.components.icon.NovaIcon
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.ArrowRight
import io.paritytech.polkadotapp.design.components.icon.vectors.Check
import io.paritytech.polkadotapp.design.components.icon.vectors.NotificationActiveOutlined
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_videogame_impl.domain.notifications.GameStartAlarmOffset
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.theme.NovaPrizesColors
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
internal fun AlertSettingsMainContent(
    selectedOffset: GameStartAlarmOffset,
    onAlertClick: () -> Unit,
    onDismiss: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(NovaPrizesColors.bottomSheetBackground)
            .padding(
                top = PolkadotTheme.spacings.small,
                bottom = PolkadotTheme.spacings.mediumIncreased
            ),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(onClick = onAlertClick)
                .padding(
                    vertical = PolkadotTheme.spacings.mediumIncreased,
                    horizontal = PolkadotTheme.spacings.large
                ),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(PolkadotTheme.spacings.small)
        ) {
            NovaIcon(
                modifier = Modifier.size(18.dp),
                imageVector = NovaIcons.NotificationActiveOutlined,
                tint = NovaPrizesColors.textPrimary
            )

            NovaText(
                modifier = Modifier.weight(1f),
                text = stringResource(RCommon.string.video_game_alert_setting_title),
                style = PolkadotTheme.typography.title.medium,
                color = NovaPrizesColors.textPrimary
            )

            NovaText(
                text = stringResource(RCommon.string.video_game_alert_offset_seconds, selectedOffset.seconds),
                style = PolkadotTheme.typography.body.large,
                color = NovaPrizesColors.textTertiary
            )

            NovaIcon(
                modifier = Modifier.size(16.dp),
                imageVector = NovaIcons.ArrowRight,
                tint = NovaPrizesColors.textTertiary
            )
        }

        HorizontalDivider(
            modifier = Modifier.padding(horizontal = PolkadotTheme.spacings.large),
            color = NovaPrizesColors.bottomSheetDivider
        )

        VerticalSpacer { mediumIncreased }

        PolkadotTextButton(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = PolkadotTheme.spacings.large),
            style = prizeGhostButtonStyle(),
            text = stringResource(RCommon.string.common_close),
            onClick = onDismiss
        )
    }
}

@Composable
private fun prizeGhostButtonStyle(): PolkadotButtonStyle {
    val content = NovaPrizesColors.textPrimary
    return remember {
        val transparent = SolidColor(Color.Transparent)
        object : PolkadotButtonStyle {
            override val colors = PolkadotButtonColors(
                containerBrush = transparent,
                contentColor = content,
                disabledContainerBrush = transparent,
                disabledContentColor = content,
            )
            override val rippleColor = content
        }
    }
}

@Composable
internal fun AlertOffsetSelectionContent(
    selectedOffset: GameStartAlarmOffset,
    onSelect: (GameStartAlarmOffset) -> Unit
) {
    val offsets = GameStartAlarmOffset.entries

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(NovaPrizesColors.bottomSheetBackground)
            .padding(vertical = PolkadotTheme.spacings.mediumIncreased)
    ) {
        offsets.fastForEachIndexed { index, offset ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onSelect(offset) }
                    .padding(
                        vertical = 10.dp,
                        horizontal = PolkadotTheme.spacings.large
                    ),
                verticalAlignment = Alignment.CenterVertically
            ) {
                NovaText(
                    modifier = Modifier.weight(1f),
                    text = stringResource(RCommon.string.video_game_alert_offset_seconds, offset.seconds),
                    style = PolkadotTheme.typography.title.medium,
                    color = NovaPrizesColors.textPrimary
                )

                if (offset == selectedOffset) {
                    NovaIcon(
                        imageVector = NovaIcons.Check,
                        tint = NovaPrizesColors.textPrimary
                    )
                }
            }

            if (index < offsets.lastIndex) {
                VerticalSpacer { small }

                HorizontalDivider(
                    modifier = Modifier.padding(horizontal = PolkadotTheme.spacings.large),
                    color = NovaPrizesColors.bottomSheetDivider
                )

                VerticalSpacer { small }
            }
        }
    }
}

@Preview
@Composable
private fun AlertSettingsMainContentPreview() {
    PolkadotTheme {
        AlertSettingsMainContent(
            selectedOffset = GameStartAlarmOffset.TEN_SECONDS,
            onAlertClick = {},
            onDismiss = {}
        )
    }
}
