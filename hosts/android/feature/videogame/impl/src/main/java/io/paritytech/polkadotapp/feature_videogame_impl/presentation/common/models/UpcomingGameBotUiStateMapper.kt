package io.paritytech.polkadotapp.feature_videogame_impl.presentation.common.models

import io.paritytech.polkadotapp.feature_videogame_api.domain.models.UpcomingGameStart
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.VideoGameRegistrationStage
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.isWaitingRoomAvailable
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.models.UpcomingGameUiState
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.models.VideoGameActionNew
import kotlin.time.Duration

fun UpcomingGameStart.toBotUi(
    registrationStage: VideoGameRegistrationStage,
    isRegistrationInProgress: Boolean,
    isGameAddedToCalendar: Boolean,
    hideAddToCalendarButton: Boolean,
    isMember: Boolean,
    isAirdropRegistrationReady: Boolean,
): UpcomingGameUiState {
    return when (this) {
        is UpcomingGameStart.Current -> toBotUiState(
            stage = registrationStage,
            inProgress = isRegistrationInProgress,
            isGameAddedToCalendar = isGameAddedToCalendar,
            hideAddToCalendarButton = hideAddToCalendarButton,
            isMember = isMember,
            isAirdropRegistrationReady = isAirdropRegistrationReady,
        )
        is UpcomingGameStart.Next -> toBotUiStateNext(isMember = isMember)
    }
}

private fun UpcomingGameStart.Current.toBotUiState(
    stage: VideoGameRegistrationStage,
    inProgress: Boolean,
    isGameAddedToCalendar: Boolean,
    hideAddToCalendarButton: Boolean,
    isMember: Boolean,
    isAirdropRegistrationReady: Boolean,
): UpcomingGameUiState {
    return when (stage) {
        VideoGameRegistrationStage.Registered -> {
            when {
                timeLeftUntilStart <= Duration.ZERO -> UpcomingGameUiState.Ongoing

                isWaitingRoomAvailable -> UpcomingGameUiState.Starting(
                    timeLeftUntilStart = timeLeftUntilStart,
                    isMember = isMember,
                )

                else -> UpcomingGameUiState.Registered(
                    timeLeftUntilStart = timeLeftUntilStart,
                    startsAt = startsAt,
                    action = VideoGameActionNew.AddToCalendar(
                        isGameAddedToCalendar = isGameAddedToCalendar,
                        hideAddToCalendarButton = hideAddToCalendarButton
                    ),
                    isMember = isMember,
                )
            }
        }

        is VideoGameRegistrationStage.CanRegister -> {
            UpcomingGameUiState.Registration(
                timeLeftUntilStart = timeLeftUntilStart,
                startsAt = startsAt,
                action = VideoGameActionNew.Register(
                    // Gated until the game's airdrop reaches its Registering phase.
                    isAvailable = isAirdropRegistrationReady,
                    inProgress = inProgress,
                    openingSoon = !isAirdropRegistrationReady,
                ),
                isMember = isMember,
            )
        }

        is VideoGameRegistrationStage.NeedsCredibilityProof -> {
            UpcomingGameUiState.Registration(
                timeLeftUntilStart = timeLeftUntilStart,
                startsAt = startsAt,
                action = VideoGameActionNew.Register(
                    // Gated like CanRegister: the runtime rejects any airdrop sign-up while the
                    // event hasn't reached Registering (Airdrop.NotAcceptingRegistrations).
                    isAvailable = isAirdropRegistrationReady,
                    inProgress = inProgress,
                    openingSoon = !isAirdropRegistrationReady,
                ),
                isMember = isMember,
            )
        }
    }
}

private fun UpcomingGameStart.Next.toBotUiStateNext(
    isMember: Boolean,
): UpcomingGameUiState {
    return UpcomingGameUiState.Registration(
        timeLeftUntilStart = timeLeftUntilStart,
        startsAt = startsAt,
        action = VideoGameActionNew.Register(
            isAvailable = false,
            inProgress = false,
            openingSoon = false,
        ),
        isMember = isMember,
    )
}
