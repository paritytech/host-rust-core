package io.paritytech.polkadotapp.feature_videogame_impl.presentation.collectibles

sealed class CollectiblesError(cause: Throwable? = null) : Throwable(cause) {
    data object UrlUnavailable : CollectiblesError()
}
