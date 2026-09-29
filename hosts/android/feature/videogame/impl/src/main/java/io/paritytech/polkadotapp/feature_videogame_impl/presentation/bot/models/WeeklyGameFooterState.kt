package io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.models

sealed interface WeeklyGameFooterState {
    data object Loading : WeeklyGameFooterState

    data object Normal : WeeklyGameFooterState

    data object OtherDimCommitted : WeeklyGameFooterState
}
