package io.paritytech.polkadotapp.feature_wallet_impl.presentation.enterAmount.domain

sealed interface SendState {
    /** Submitted, but the coins are not on chain yet. */
    data object Detecting : SendState

    /** On chain and waiting for the recipient to take them. */
    data object Detected : SendState

    data object Complete : SendState

    data class Failed(val error: Throwable) : SendState
}
