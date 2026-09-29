package io.paritytech.polkadotapp.feature_videogame_impl.presentation.notifications

import android.content.Context
import android.content.Intent
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.core.net.toUri
import androidx.fragment.app.viewModels
import dagger.hilt.android.AndroidEntryPoint
import io.paritytech.polkadotapp.common.presentation.notifications.permissionAsker.NotificationPermissionRequestConfig
import io.paritytech.polkadotapp.common.presentation.notifications.permissionAsker.compose.NotificationPermissionAsker
import io.paritytech.polkadotapp.common.presentation.screens.BaseComposeFragment
import io.paritytech.polkadotapp.common.utils.canScheduleExactAlarms
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.Clock
import io.paritytech.polkadotapp.design.components.icon.vectors.DoneAll
import io.paritytech.polkadotapp.design.components.icon.vectors.MoneyFilled
import io.paritytech.polkadotapp.common.R as RCommon

@AndroidEntryPoint
class VideoGameNotificationsFragment : BaseComposeFragment<VideoGameNotificationsViewModel>() {
    override val viewModel: VideoGameNotificationsViewModel by viewModels()

    @Composable
    override fun Screen() {
        val context = LocalContext.current
        val contract = viewModel as VideoGameNotificationsContract

        val launcher = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            // Check the alarm permission again because the activity result returns CANCELED
            // even if the user has granted the permission contrary to what is written in the documentation
            contract.resolvePermissionRequest(context.canScheduleExactAlarms())
        }

        NotificationPermissionAsker(
            config = remember { createNotificationPermissionRequestConfig() },
            onGranted = {
                context.createAlarmManagerIntentIfNeeded()?.let {
                    launcher.launch(it)
                } ?: contract.resolvePermissionRequest(true)
            },
            onDenied = {
                contract.resolvePermissionRequest(false)
            },
            onCloseClicked = { contract.back() }
        )
    }
}

private fun Context.createAlarmManagerIntentIfNeeded(): Intent? {
    return if (canScheduleExactAlarms().not()) {
        Intent(
            Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
            "package:$packageName".toUri()
        )
    } else null
}

private fun createNotificationPermissionRequestConfig() = NotificationPermissionRequestConfig(
    titleRes = RCommon.string.video_game_notifications_permission_request_title,
    rationaleTitleRes = RCommon.string.video_game_notifications_permission_rationale_title,
    rationaleMessageRes = RCommon.string.video_game_notifications_permission_rationale_message,
    benefits = listOf(
        NotificationPermissionRequestConfig.Benefit(
            icon = NovaIcons.Clock,
            descriptionRes = RCommon.string.video_game_notifications_permission_request_benefit_1
        ),
        NotificationPermissionRequestConfig.Benefit(
            icon = NovaIcons.DoneAll,
            descriptionRes = RCommon.string.video_game_notifications_permission_request_benefit_2
        ),
        NotificationPermissionRequestConfig.Benefit(
            icon = NovaIcons.MoneyFilled,
            descriptionRes = RCommon.string.video_game_notifications_permission_request_benefit_3
        ),
    )
)
