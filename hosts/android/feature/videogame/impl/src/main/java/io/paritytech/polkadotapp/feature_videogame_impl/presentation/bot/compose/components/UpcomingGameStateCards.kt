package io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.compose.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.common.presentation.formatters.time.LocalTimeFormatter
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.models.UpcomingGameUiState
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.theme.NovaPrizesColors
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.theme.NovaGameTypography
import io.paritytech.polkadotapp.common.R as RCommon

private val PrizesCardTopLabelStyle = NovaGameTypography.prizesCardTopLabel
private val PrizesCardMainTextStyle = NovaGameTypography.prizesCardMainText

private val CARD_PADDING = 24.dp

private const val NBSP = '\u00A0'

@Composable
internal fun RegistrationCard(state: UpcomingGameUiState.Registration) {
    GameStateCard(
        palette = UpcomingGameStickerPalette.BLUE,
        topLabel = stringResource(RCommon.string.chat_bot_prizes_next_game_label),
        mainContent = { CardDate(state.startsAt) },
        isMember = state.isMember,
    )
}

@Composable
internal fun RegisteredCard(state: UpcomingGameUiState.Registered) {
    GameStateCard(
        palette = UpcomingGameStickerPalette.GREEN,
        topLabel = stringResource(RCommon.string.chat_bot_prizes_next_game_label),
        mainContent = { CardDate(state.startsAt) },
        isMember = state.isMember,
    )
}

@Composable
internal fun StartingCard(state: UpcomingGameUiState.Starting) {
    GameStateCard(
        palette = UpcomingGameStickerPalette.YELLOW,
        topLabel = stringResource(RCommon.string.chat_bot_prizes_next_game_label),
        mainContent = { CardMainText(LocalTimeFormatter.current.formatTimeLeft(state.timeLeftUntilStart)) },
        isMember = state.isMember,
    )
}

@Composable
internal fun OngoingCard() {
    GameStateCard(
        palette = UpcomingGameStickerPalette.YELLOW,
        topLabel = stringResource(RCommon.string.chat_bot_prizes_game_live_label),
        mainContent = { CardMainText(stringResource(RCommon.string.chat_bot_weekly_game_state_game_ongoing_message)) },
    )
}

@Composable
private fun GameStateCard(
    palette: UpcomingGameStickerPalette,
    topLabel: String,
    mainContent: @Composable () -> Unit,
    isMember: Boolean = false,
) {
    val membershipBanner = if (isMember) {
        stringResource(RCommon.string.chat_bot_prizes_play_to_retain_membership)
    } else {
        null
    }
    UpcomingGameStickerFrame(palette = palette, membershipBanner = membershipBanner) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(CARD_PADDING),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            NovaText(
                text = topLabel,
                style = PrizesCardTopLabelStyle,
                color = NovaPrizesColors.textPrimary,
                textAlign = TextAlign.Center,
            )
            VerticalSpacer { extraSmall }
            mainContent()
        }
    }
}

@Composable
private fun CardDate(timestamp: Long) {
    val timeFormatter = LocalTimeFormatter.current
    CardMainText(remember(timestamp) { timeFormatter.formatDateWithWeekday(timestamp, includeYear = false) })
    CardMainText(remember(timestamp) { timeFormatter.formatTime(timestamp).replace(' ', NBSP) })
}

@Composable
private fun CardMainText(text: String) {
    NovaText(
        text = text,
        style = PrizesCardMainTextStyle,
        color = NovaPrizesColors.textPrimary,
        textAlign = TextAlign.Center,
    )
}
