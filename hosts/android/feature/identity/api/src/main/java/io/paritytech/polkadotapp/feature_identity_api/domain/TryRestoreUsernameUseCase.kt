package io.paritytech.polkadotapp.feature_identity_api.domain

interface TryRestoreUsernameUseCase {
    suspend operator fun invoke(): Boolean
}
