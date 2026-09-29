package io.paritytech.polkadotapp.feature_upgrade_username_api.domain.usecase

import io.paritytech.polkadotapp.feature_upgrade_username_api.domain.model.UpgradeToFullUsernameState
import kotlinx.coroutines.flow.Flow

interface ReadyToUpgradeUsernameUseCase {
    operator fun invoke(): Flow<UpgradeToFullUsernameState>
}
