@file:OptIn(ExperimentalMaterial3Api::class)

package io.paritytech.polkadotapp.common.presentation.notifications.permissionAsker.compose

import android.Manifest.permission.POST_NOTIFICATIONS
import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.common.presentation.notifications.permissionAsker.NotificationPermissionRequestConfig
import io.paritytech.polkadotapp.common.presentation.notifications.permissionAsker.compose.components.BenefitItem
import io.paritytech.polkadotapp.common.presentation.notifications.permissionAsker.compose.components.RationalContent
import io.paritytech.polkadotapp.common.utils.permissions.PermissionAsker
import io.paritytech.polkadotapp.common.utils.permissions.PermissionResult
import io.paritytech.polkadotapp.design.components.bottomsheet.NovaModalBottomSheet
import io.paritytech.polkadotapp.design.components.button.common.PolkadotButtonStyle
import io.paritytech.polkadotapp.design.components.button.default.PolkadotTextButton
import io.paritytech.polkadotapp.design.components.icon.NovaIcon
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.Info
import io.paritytech.polkadotapp.design.components.icon.vectors.Upload
import io.paritytech.polkadotapp.design.components.spacer.HorizontalSpacer
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun NotificationPermissionAsker(
    config: NotificationPermissionRequestConfig,
    onGranted: () -> Unit,
    onDenied: () -> Unit,
    onCloseClicked: () -> Unit
) {
    val activity = LocalActivity.current ?: return
    var showRationale by remember { mutableStateOf(false) }

    val permissionLauncher = rememberPermissionAsker()

    val onPermissionAskResult: (PermissionResult) -> Unit = { result ->
        when (result) {
            PermissionResult.GRANTED -> onGranted()
            PermissionResult.DENIED -> onDenied()
            PermissionResult.DENIED_FOREVER -> {
                showRationale = true
            }
        }
    }

    NotificationPermissionAskerInternal(
        onEnableClicked = { permissionLauncher.requestPushNotificationPermissions(activity, onPermissionAskResult) },
        onCancelClicked = { showRationale = true },
        config = config
    )

    NovaModalBottomSheet(
        isVisible = showRationale,
        onDismissRequest = { showRationale = false },
    ) {
        RationalContent(
            title = stringResource(config.rationaleTitleRes),
            message = stringResource(config.rationaleMessageRes),
            onEnable = {
                showRationale = false
                permissionLauncher.requestPushNotificationPermissions(activity, onPermissionAskResult)
            },
            onCancel = onCloseClicked
        )
    }
}

private fun PermissionAsker.requestPushNotificationPermissions(activity: Activity, onResult: (PermissionResult) -> Unit) {
    if (getPermissionState(POST_NOTIFICATIONS) == PermissionResult.DENIED_FOREVER) {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", activity.packageName, null)
        }
        activity.startActivity(intent)
    } else {
        askPermission(POST_NOTIFICATIONS, onResult = onResult)
    }
}

@Composable
private fun NotificationPermissionAskerInternal(
    onEnableClicked: () -> Unit,
    onCancelClicked: () -> Unit,
    config: NotificationPermissionRequestConfig,
) {
    PolkadotSurface {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .systemBarsPadding()
                .padding(
                    start = PolkadotTheme.spacings.large,
                    end = PolkadotTheme.spacings.large,
                    top = 48.dp,
                    bottom = PolkadotTheme.spacings.mediumIncreased
                ),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            NovaText(
                modifier = Modifier.padding(horizontal = 28.dp),
                text = stringResource(config.titleRes),
                style = PolkadotTheme.typography.headline.large,
                color = PolkadotTheme.colors.fg.primary,
                textAlign = TextAlign.Center,
            )

            VerticalSpacer { extraLargeIncreased }

            LazyColumn(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(PolkadotTheme.spacings.small)
            ) {
                items(config.benefits) {
                    BenefitItem(
                        modifier = Modifier.fillMaxWidth(),
                        icon = it.icon,
                        description = stringResource(it.descriptionRes)
                    )
                }
            }

            PolkadotSurface(
                modifier = Modifier.fillMaxWidth(),
                shape = PolkadotTheme.shapes.mediumIncreased,
                border = BorderStroke(PolkadotTheme.borders.default, PolkadotTheme.colors.stroke.primary)
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(PolkadotTheme.spacings.mediumIncreased),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    NovaText(
                        modifier = Modifier.weight(1f),
                        text = getWarningString(),
                        style = PolkadotTheme.typography.body.medium,
                        color = PolkadotTheme.colors.fg.primary,
                        textAlign = TextAlign.Start,
                    )

                    HorizontalSpacer { large }

                    NovaIcon(
                        modifier = Modifier
                            .padding(10.dp)
                            .size(30.dp),
                        imageVector = NovaIcons.Info,
                        tint = PolkadotTheme.colors.fg.tertiary
                    )
                }
            }

            VerticalSpacer { extraLarge }

            PolkadotTextButton(
                modifier = Modifier.fillMaxWidth(),
                text = stringResource(RCommon.string.notification_permission_request_ok_button),
                style = PolkadotButtonStyle.primary(),
                onClick = onEnableClicked
            )

            VerticalSpacer { mediumIncreased }

            PolkadotTextButton(
                modifier = Modifier.fillMaxWidth(),
                text = stringResource(RCommon.string.notification_permission_request_nah_button),
                style = PolkadotButtonStyle.ghost(),
                onClick = onCancelClicked
            )
        }
    }
}

@Composable
private fun getWarningString(): AnnotatedString {
    val primaryText: String = stringResource(RCommon.string.notifications_permission_warning_highlighted)
    val secondaryText: String = stringResource(RCommon.string.notifications_permission_warning_default)
    return buildAnnotatedString {
        withStyle(
            style = PolkadotTheme.typography.body.medium.copy(
                color = PolkadotTheme.colors.fg.primary,
            ).toSpanStyle()
        ) {
            append(primaryText)
        }

        append(" ")

        withStyle(
            style = PolkadotTheme.typography.body.medium.copy(
                color = PolkadotTheme.colors.fg.secondary,
            ).toSpanStyle()
        ) {
            append(secondaryText)
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun NotificationPermissionRequestScreenPreview() {
    PolkadotTheme {
        NotificationPermissionAskerInternal(
            onEnableClicked = {},
            onCancelClicked = {},
            config = NotificationPermissionRequestConfig(
                titleRes = RCommon.string.become_citizen_notification_permission_request_title,
                rationaleTitleRes = RCommon.string.become_citizen_notification_permission_rationale_title,
                rationaleMessageRes = RCommon.string.become_citizen_notification_permission_rationale_message,
                benefits = listOf(
                    NotificationPermissionRequestConfig.Benefit(
                        icon = NovaIcons.Upload,
                        descriptionRes = RCommon.string.become_citizen_notification_permission_request_benefit_1
                    ),
                )
            )
        )
    }
}
