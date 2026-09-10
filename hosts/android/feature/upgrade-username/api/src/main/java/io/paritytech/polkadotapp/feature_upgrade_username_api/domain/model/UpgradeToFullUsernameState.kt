package io.paritytech.polkadotapp.feature_upgrade_username_api.domain.model

import io.paritytech.polkadotapp.feature_usernames_api.domain.model.Username

sealed interface UpgradeToFullUsernameState {
    object NotReady : UpgradeToFullUsernameState

    class Ready(val liteUsername: Username) : UpgradeToFullUsernameState

    class Completed(val liteUsername: Username, val fullUsername: Username) : UpgradeToFullUsernameState
}
