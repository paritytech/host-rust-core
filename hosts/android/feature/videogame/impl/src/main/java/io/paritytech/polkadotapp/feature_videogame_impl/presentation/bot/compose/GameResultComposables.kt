package io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.compose

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.util.fastForEachIndexed
import io.paritytech.polkadotapp.common.R
import io.paritytech.polkadotapp.common.domain.model.Timestamp
import io.paritytech.polkadotapp.common.presentation.formatters.time.LocalTimeFormatter
import io.paritytech.polkadotapp.common.presentation.formatters.time.TimeFormatter
import io.paritytech.polkadotapp.design.components.icon.NovaIcon
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.Check
import io.paritytech.polkadotapp.design.components.icon.vectors.Clock
import io.paritytech.polkadotapp.design.components.image.NovaAsyncImage
import io.paritytech.polkadotapp.design.components.spacer.HorizontalSpacer
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_videogame_impl.domain.bot.messages.gameResult.model.FailedPastGameScoring
import io.paritytech.polkadotapp.feature_videogame_impl.domain.bot.messages.gameResult.model.PastGameOutcome
import io.paritytech.polkadotapp.feature_videogame_impl.domain.bot.messages.gameResult.model.SuccessPastGameScoring
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.theme.NovaPrizesColors
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.persistentListOf

private val CARD_RADIUS = 16.dp
private val CARD_PADDING = 24.dp
private val CHAT_PLAYERS_HEIGHT = 52.dp
private val CHAT_PLAYERS_RADIUS = 12.dp

private val ResultTopLabelStyle = TextStyle(
    fontSize = 16.sp,
    lineHeight = 20.sp,
    fontWeight = FontWeight.SemiBold,
)
private val ResultMainDateStyle = TextStyle(
    fontSize = 24.sp,
    lineHeight = 32.sp,
    fontWeight = FontWeight.SemiBold,
)
private val ResultSecondaryStyle = TextStyle(
    fontSize = 14.sp,
    lineHeight = 20.sp,
    fontWeight = FontWeight.Normal,
)
private val ResultSecondaryColor = NovaPrizesColors.pastGameSecondaryText
private val ResultCardBorderColor = NovaPrizesColors.pastGameCardBorder

@Composable
fun PastGameCard(outcome: PastGameOutcome, timestamp: Timestamp) {
    val styling = outcome.cardStyling()
    val secondaryText = getSecondaryText(outcome).takeIf { it.isNotEmpty() }
    val timeFormatter = LocalTimeFormatter.current

    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        PolkadotSurface(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(CARD_RADIUS),
            color = NovaPrizesColors.cardInnerBg,
            border = BorderStroke(PolkadotTheme.borders.default, ResultCardBorderColor),
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(CARD_PADDING),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    styling.icon?.let { icon ->
                        NovaIcon(
                            modifier = Modifier.size(16.dp),
                            imageVector = icon,
                            tint = styling.accentColor,
                        )
                        HorizontalSpacer { small }
                    }
                    NovaText(
                        text = stringResource(outcome.getTitleRes()),
                        style = ResultTopLabelStyle,
                        color = styling.accentColor,
                    )
                }

                VerticalSpacer { small }

                NovaText(
                    text = remember(timestamp) { timeFormatter.formatGameDateTime(timestamp) },
                    style = ResultMainDateStyle,
                    color = NovaPrizesColors.textPrimary,
                    textAlign = TextAlign.Center,
                )
            }
        }

        if (secondaryText != null) {
            VerticalSpacer { small }
            NovaText(
                modifier = Modifier.fillMaxWidth(),
                text = secondaryText,
                style = ResultSecondaryStyle,
                color = ResultSecondaryColor,
                textAlign = TextAlign.Center,
            )
        }
    }
}

private data class GameResultStyling(
    val icon: ImageVector?,
    val accentColor: Color,
)

@Composable
private fun PastGameOutcome.cardStyling(): GameResultStyling = when (this) {
    is PastGameOutcome.Success -> GameResultStyling(
        icon = NovaIcons.Check,
        accentColor = NovaPrizesColors.gameSucceededAccent,
    )
    is PastGameOutcome.Failed -> GameResultStyling(
        icon = null,
        accentColor = NovaPrizesColors.gameEndedTitle,
    )
    is PastGameOutcome.Pending -> GameResultStyling(
        icon = NovaIcons.Clock,
        accentColor = NovaPrizesColors.warning,
    )
}

private const val AVATAR_SIZE = 24
private const val AVATAR_OVERLAP = 8

@Composable
fun ChatWithPlayers(
    playerAvatarPaths: ImmutableList<String>,
    onClick: () -> Unit,
) {
    if (playerAvatarPaths.isNotEmpty()) {
        PolkadotSurface(
            modifier = Modifier
                .fillMaxWidth()
                .height(CHAT_PLAYERS_HEIGHT),
            shape = RoundedCornerShape(CHAT_PLAYERS_RADIUS),
            color = NovaPrizesColors.chatWithPlayersBackground,
            border = BorderStroke(PolkadotTheme.borders.default, NovaPrizesColors.cardStroke),
            onClick = onClick,
            contentAlignment = Alignment.Center,
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center,
            ) {
                OverlappingAvatars(avatarPaths = playerAvatarPaths)
                HorizontalSpacer { small }
                NovaText(
                    text = stringResource(R.string.chat_bot_weekly_game_result_chat_with_players),
                    style = ResultTopLabelStyle,
                    color = NovaPrizesColors.textPrimary,
                )
            }
        }
    }
}

@Composable
private fun OverlappingAvatars(avatarPaths: ImmutableList<String>) {
    val totalWidth = (avatarPaths.size * AVATAR_SIZE) - ((avatarPaths.size - 1) * AVATAR_OVERLAP)

    Box(modifier = Modifier.size(width = totalWidth.dp, height = AVATAR_SIZE.dp)) {
        avatarPaths.fastForEachIndexed { index, uri ->
            val offsetX = (index * (AVATAR_SIZE - AVATAR_OVERLAP)).dp

            NovaAsyncImage(
                modifier = Modifier
                    .graphicsLayer { translationX = offsetX.toPx() }
                    .size(AVATAR_SIZE.dp)
                    .clip(PolkadotTheme.shapes.full)
                    .border(PolkadotTheme.borders.default, NovaPrizesColors.avatarRing, PolkadotTheme.shapes.full)
                    .background(NovaPrizesColors.avatarPlaceholderBg),
                model = uri,
                contentScale = ContentScale.Crop,
            )
        }
    }
}

@Preview
@Composable
private fun PastGameCardPreview() {
    PolkadotTheme {
        CompositionLocalProvider(
            LocalTimeFormatter provides TimeFormatter.mocked(LocalContext.current),
        ) {
            Column(
                verticalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.padding(16.dp),
            ) {
                PastGameCard(
                    outcome = PastGameOutcome.Success(SuccessPastGameScoring.PersonhoodStateUnknown),
                    timestamp = System.currentTimeMillis(),
                )
                ChatWithPlayers(
                    playerAvatarPaths = persistentListOf("a", "b", "c"),
                    onClick = {},
                )
                PastGameCard(
                    outcome = PastGameOutcome.Failed(FailedPastGameScoring.Playing(gamesLeft = 1, hasSuspendedPersonhood = false)),
                    timestamp = System.currentTimeMillis(),
                )
                PastGameCard(
                    outcome = PastGameOutcome.Pending,
                    timestamp = System.currentTimeMillis(),
                )
            }
        }
    }
}
