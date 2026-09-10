package io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.models

sealed interface VideoGameActionNew {
    // openingSoon = disabled specifically because the game's airdrop registration hasn't opened yet
    // (distinct from other unavailable reasons); the UI renders an "Opening soon" label for it.
    data class Register(
        val isAvailable: Boolean,
        val inProgress: Boolean,
        val openingSoon: Boolean,
    ) : VideoGameActionNew
    data object StartPlaying : VideoGameActionNew
    data class AddToCalendar(val isGameAddedToCalendar: Boolean, val hideAddToCalendarButton: Boolean) : VideoGameActionNew
}
