package io.paritytech.polkadotapp.feature_identity_api.domain.models

sealed interface IdentityCredentialState {
    data object NotAdded : IdentityCredentialState
    data object Review : IdentityCredentialState
    data object Rejected : IdentityCredentialState
    data class Confirmed(val username: String) : IdentityCredentialState
}
