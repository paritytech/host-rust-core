package io.paritytech.polkadotapp.feature_videogame_impl.presentation.common.compose

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import io.paritytech.polkadotapp.common.presentation.formatters.time.LocalTimeFormatter
import io.paritytech.polkadotapp.design.components.button.default.PolkadotTextButton
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.common.models.VideoGameAction
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun VideoGameAction(
    modifier: Modifier,
    action: VideoGameAction,
    onRegister: () -> Unit,
    onStartPlaying: () -> Unit,
    onDeposit: () -> Unit
) {
    when (action) {
        is VideoGameAction.Deposit -> {
            DepositAction(modifier, onDeposit)
        }

        is VideoGameAction.Register -> {
            RegisterAction(modifier, action, onRegister)
        }

        is VideoGameAction.StartPlaying -> {
            StartPlayingAction(modifier, action, onStartPlaying)
        }
    }
}

@Composable
private fun DepositAction(
    modifier: Modifier,
    onDeposit: () -> Unit
) {
    PolkadotTextButton(
        modifier = modifier,
        text = stringResource(RCommon.string.video_game_home_add_deposit_action),
        onClick = onDeposit
    )
}

@Composable
private fun RegisterAction(
    modifier: Modifier,
    action: VideoGameAction.Register,
    onRegister: () -> Unit
) {
    when (action.availability) {
        is VideoGameAction.Availability.Available -> {
            PolkadotTextButton(
                modifier = modifier,
                text = stringResource(RCommon.string.video_game_home_register_action),
                loading = action.inProgress,
                onClick = onRegister
            )
        }

        is VideoGameAction.Availability.AvailableIn -> {
            val timeFormatter = LocalTimeFormatter.current

            PolkadotTextButton(
                modifier = modifier,
                text = stringResource(
                    RCommon.string.video_game_home_register_in_action,
                    timeFormatter.formatTimeLeft(action.availability.timeLeft)
                ),
                loading = action.inProgress,
                enabled = false,
                onClick = {}
            )
        }
    }
}

@Composable
private fun StartPlayingAction(
    modifier: Modifier,
    action: VideoGameAction.StartPlaying,
    onStartPlaying: () -> Unit
) {
    when (action.availability) {
        is VideoGameAction.Availability.Available -> {
            PolkadotTextButton(
                modifier = modifier,
                text = stringResource(RCommon.string.video_game_home_start_playing_action),
                onClick = onStartPlaying
            )
        }

        is VideoGameAction.Availability.AvailableIn -> {
            val timeFormatter = LocalTimeFormatter.current

            PolkadotTextButton(
                modifier = modifier,
                text = stringResource(
                    RCommon.string.video_game_home_start_playing_in_action,
                    timeFormatter.formatTimeLeft(action.availability.timeLeft)
                ),
                enabled = false,
                onClick = {}
            )
        }
    }
}
