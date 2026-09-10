package io.paritytech.polkadotapp.feature_upgrade_username_api.domain.model

sealed interface UpgradeUsernameAvailabilityState {
    data object Free : UpgradeUsernameAvailabilityState
    data object ReservedByUs : UpgradeUsernameAvailabilityState
    data object NotAvailable : UpgradeUsernameAvailabilityState
}
