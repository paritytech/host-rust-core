package io.paritytech.polkadotapp.feature_upgrade_username_impl.presentation.upgrade

/**
 * Local to this screen: its failures come from the dotNS gateway on chain, not the backend, so
 * it does not share a state model with the claim screen.
 */
enum class UpgradeUsernameFieldState { Neutral, Taken, Invalid, Available }
