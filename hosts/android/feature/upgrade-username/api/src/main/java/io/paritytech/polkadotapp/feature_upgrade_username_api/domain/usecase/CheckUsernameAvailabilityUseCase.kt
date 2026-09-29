package io.paritytech.polkadotapp.feature_upgrade_username_api.domain.usecase

import io.paritytech.polkadotapp.feature_upgrade_username_api.domain.model.UpgradeUsernameAvailabilityState

/**
 * Checks whether [username] can be claimed on the People chain: unowned, and not blocked by a
 * live reservation ahead of us in the queue. Shared so the game-results claim prompt and the
 * username-upgrade flow can't drift apart.
 */
interface CheckUsernameAvailabilityUseCase {
    suspend operator fun invoke(username: String): Result<UpgradeUsernameAvailabilityState>
}
