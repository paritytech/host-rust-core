package io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.compose

import androidx.annotation.StringRes
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import io.paritytech.polkadotapp.common.R
import io.paritytech.polkadotapp.feature_videogame_impl.domain.bot.messages.gameResult.model.PastGameOutcome
import io.paritytech.polkadotapp.feature_videogame_impl.domain.bot.messages.gameResult.model.SuccessPastGameScoring

@StringRes
fun PastGameOutcome.getTitleRes(): Int = when (this) {
    is PastGameOutcome.Pending -> R.string.chat_bot_weekly_game_result_pending
    is PastGameOutcome.Success -> R.string.chat_bot_weekly_game_result_success
    is PastGameOutcome.Failed -> R.string.chat_bot_weekly_game_result_failed
}

@Composable
fun getSecondaryText(gameOutcome: PastGameOutcome): String {
    return when (gameOutcome) {
        is PastGameOutcome.Failed -> stringResource(R.string.chat_bot_weekly_game_result_failed_subtitle)
        is PastGameOutcome.Pending -> stringResource(R.string.chat_bot_weekly_game_result_pending_description)
        is PastGameOutcome.Success -> getSecondaryText(gameOutcome.scoring)
    }
}

@Composable
private fun getSecondaryText(successScoring: SuccessPastGameScoring) = when (successScoring) {
    SuccessPastGameScoring.ExternallyRecognized -> stringResource(R.string.chat_bot_weekly_game_result_success_external_description)
    SuccessPastGameScoring.PersonhoodStateUnknown -> ""
    is SuccessPastGameScoring.Playing -> if (successScoring.hasSuspendedPersonhood) {
        stringResource(R.string.chat_bot_weekly_game_result_success_paused_description, successScoring.gamesLeft)
    } else {
        stringResource(R.string.chat_bot_weekly_game_result_success_description, successScoring.gamesLeft)
    }

    SuccessPastGameScoring.ReachedPersonhood -> stringResource(R.string.chat_bot_weekly_game_result_success_personhood_description)
    SuccessPastGameScoring.AlreadyReachedPersonhood -> ""
}
