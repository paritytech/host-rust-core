package io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.compose.components

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.tooling.preview.PreviewParameter
import androidx.compose.ui.tooling.preview.PreviewParameterProvider
import io.paritytech.polkadotapp.common.presentation.formatters.time.LocalTimeFormatter
import io.paritytech.polkadotapp.common.presentation.formatters.time.TimeFormatter
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.models.UpcomingGameUiState
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.models.VideoGameActionNew
import kotlin.time.Duration.Companion.seconds

@Composable
fun UpcomingGameWidget(
    modifier: Modifier,
    upcomingGame: UpcomingGameUiState,
    onRegister: () -> Unit,
    onStartPlaying: () -> Unit,
    onAddToCalendar: () -> Unit
) {
    AnimatedContent(
        modifier = modifier,
        targetState = upcomingGame,
        contentKey = { it::class },
        transitionSpec = {
            (fadeIn(tween(STATE_TRANSITION_MS)) togetherWith fadeOut(tween(STATE_TRANSITION_MS)))
                .using(SizeTransform(clip = false))
        },
        label = "UpcomingGameState",
    ) { state ->
        Column(Modifier.fillMaxWidth()) {
            when (state) {
                is UpcomingGameUiState.Registration -> RegistrationCard(state)
                is UpcomingGameUiState.Registered -> RegisteredCard(state)
                is UpcomingGameUiState.Starting -> StartingCard(state)
                is UpcomingGameUiState.Ongoing -> OngoingCard()
            }

            val action = state.action
            if (action != null) {
                VerticalSpacer { extraSmall }

                ActionArea(
                    action = action,
                    onRegister = onRegister,
                    onStartPlaying = onStartPlaying,
                    onAddToCalendar = onAddToCalendar
                )
            }
        }
    }
}

private const val STATE_TRANSITION_MS = 500

@Preview
@Composable
private fun UpcomingGameWidgetPreview(
    @PreviewParameter(UpcomingGameUiStateProvider::class) model: UpcomingGamePreviewModel
) {
    PolkadotTheme {
        CompositionLocalProvider(
            LocalTimeFormatter provides TimeFormatter.mocked(LocalContext.current)
        ) {
            UpcomingGameWidget(
                modifier = Modifier.fillMaxWidth(),
                upcomingGame = model.state,
                onRegister = { },
                onStartPlaying = { },
                onAddToCalendar = { }
            )
        }
    }
}

private data class UpcomingGamePreviewModel(
    val name: String,
    val state: UpcomingGameUiState
)

private class UpcomingGameUiStateProvider : PreviewParameterProvider<UpcomingGamePreviewModel> {
    private val items = listOf(
        UpcomingGamePreviewModel(
            name = "Registration",
            state = UpcomingGameUiState.Registration(
                timeLeftUntilStart = 10.seconds,
                startsAt = System.currentTimeMillis(),
                action = VideoGameActionNew.Register(isAvailable = true, inProgress = false, openingSoon = false),
                isMember = false,
            )
        ),
        UpcomingGamePreviewModel(
            name = "Registered",
            state = UpcomingGameUiState.Registered(
                timeLeftUntilStart = 10.seconds,
                startsAt = System.currentTimeMillis(),
                action = VideoGameActionNew.AddToCalendar(isGameAddedToCalendar = false, hideAddToCalendarButton = false),
                isMember = false,
            )
        ),
        UpcomingGamePreviewModel(
            name = "Starting",
            state = UpcomingGameUiState.Starting(
                timeLeftUntilStart = 10.seconds,
                isMember = false,
            )
        ),
        UpcomingGamePreviewModel(
            name = "Ongoing",
            state = UpcomingGameUiState.Ongoing
        ),
    )

    override val values: Sequence<UpcomingGamePreviewModel> = items.asSequence()

    override fun getDisplayName(index: Int): String? = items.getOrNull(index)?.name
}
