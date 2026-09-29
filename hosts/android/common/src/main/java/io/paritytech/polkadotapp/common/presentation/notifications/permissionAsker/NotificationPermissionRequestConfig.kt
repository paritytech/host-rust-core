package io.paritytech.polkadotapp.common.presentation.notifications.permissionAsker

import androidx.compose.ui.graphics.vector.ImageVector

class NotificationPermissionRequestConfig(
    val titleRes: Int,
    val benefits: List<Benefit>,
    val rationaleTitleRes: Int,
    val rationaleMessageRes: Int
) {
    class Benefit(
        val icon: ImageVector,
        val descriptionRes: Int
    )
}
