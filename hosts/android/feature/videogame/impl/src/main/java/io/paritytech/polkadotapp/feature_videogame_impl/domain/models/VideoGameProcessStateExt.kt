package io.paritytech.polkadotapp.feature_videogame_impl.domain.models

internal fun VideoGameProcessState.requiresLocalCamera(): Boolean = when (this) {
    is VideoGameProcessState.WaitingRoom -> preConnection != null
    is VideoGameProcessState.Round -> true
    is VideoGameProcessState.Reporting,
    is VideoGameProcessState.Finished,
    is VideoGameProcessState.Error -> false
}
