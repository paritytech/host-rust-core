package io.paritytech.polkadotapp.feature_videogame_impl.presentation.addToCalendar.compose

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.design.components.button.common.PolkadotButtonStyle
import io.paritytech.polkadotapp.design.components.button.default.PolkadotButton
import io.paritytech.polkadotapp.design.components.button.default.PolkadotTextButton
import io.paritytech.polkadotapp.design.components.icon.NovaIcon
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.NotificationsBellOutlined
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_videogame_impl.R
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.addToCalendar.VideoGameAddToCalendarContract
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun VideoGameAddToCalendarScreen(contract: VideoGameAddToCalendarContract) {
    VideoGameAddToCalendarScreenInternal(
        onConfirm = contract::confirm,
        onDecline = contract::decline
    )
}

@Composable
private fun VideoGameAddToCalendarScreenInternal(
    onConfirm: () -> Unit,
    onDecline: () -> Unit
) {
    PolkadotSurface {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .systemBarsPadding()
                .padding(
                    start = PolkadotTheme.spacings.large,
                    end = PolkadotTheme.spacings.large,
                    top = 48.dp,
                    bottom = PolkadotTheme.spacings.mediumIncreased
                ),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            NovaText(
                text = stringResource(RCommon.string.video_game_add_to_calendar_title),
                style = PolkadotTheme.typography.headline.large,
                color = PolkadotTheme.colors.fg.primary,
                textAlign = TextAlign.Center
            )

            VerticalSpacer { extraMedium }

            NovaText(
                text = stringResource(RCommon.string.video_game_add_to_calendar_description),
                style = PolkadotTheme.typography.body.large,
                color = PolkadotTheme.colors.fg.secondary,
                textAlign = TextAlign.Center
            )

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f),
                contentAlignment = Alignment.Center
            ) {
                Image(
                    painter = painterResource(R.drawable.img_calendar_notifications),
                    contentDescription = "calendar_notifications",
                )
            }

            PolkadotButton(
                modifier = Modifier.fillMaxWidth(),
                style = PolkadotButtonStyle.primary(),
                onClick = onConfirm
            ) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(PolkadotTheme.spacings.small),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    NovaIcon(
                        imageVector = NovaIcons.NotificationsBellOutlined
                    )

                    NovaText(text = stringResource(RCommon.string.video_game_add_to_calendar_add_action))
                }
            }

            VerticalSpacer { small }

            PolkadotTextButton(
                modifier = Modifier.fillMaxWidth(),
                text = stringResource(RCommon.string.video_game_add_to_calendar_later_action),
                style = PolkadotButtonStyle.ghost(),
                onClick = onDecline
            )
        }
    }
}

@Preview
@Composable
private fun VideoGameAddToCalendarScreenPreview() {
    PolkadotTheme {
        VideoGameAddToCalendarScreenInternal(
            onConfirm = {},
            onDecline = {}
        )
    }
}
