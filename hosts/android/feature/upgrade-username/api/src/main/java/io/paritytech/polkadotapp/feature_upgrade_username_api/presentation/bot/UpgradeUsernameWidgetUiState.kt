package io.paritytech.polkadotapp.feature_upgrade_username_api.presentation.bot

import io.paritytech.polkadotapp.feature_upgrade_username_api.domain.model.UpgradeToFullUsernameState

class UpgradeUsernameWidgetUiState(
    val fullName: String,
    val liteName: String,
    val isUpgraded: Boolean
)

fun UpgradeToFullUsernameState.toBotUi(): UpgradeUsernameWidgetUiState? = when (this) {
    UpgradeToFullUsernameState.NotReady -> null

    is UpgradeToFullUsernameState.Ready -> UpgradeUsernameWidgetUiState(
        fullName = liteUsername.base,
        liteName = liteUsername.getDisplayUsername(),
        isUpgraded = false
    )

    is UpgradeToFullUsernameState.Completed -> UpgradeUsernameWidgetUiState(
        fullName = fullUsername.getDisplayUsername(),
        liteName = liteUsername.getDisplayUsername(),
        isUpgraded = true
    )
}
