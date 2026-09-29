package io.paritytech.polkadotapp.feature_people_api.domain.dim

typealias DimId = String

sealed class DimState {
    data object NotStarted : DimState()
    data class Started(val cancellable: Boolean) : DimState()
}
