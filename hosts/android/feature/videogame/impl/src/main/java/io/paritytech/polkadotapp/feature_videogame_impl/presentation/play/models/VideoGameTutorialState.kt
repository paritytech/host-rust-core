package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.models

sealed interface VideoGameTutorialState {
    data object Shown : VideoGameTutorialState
    data object Hidden : VideoGameTutorialState
}
