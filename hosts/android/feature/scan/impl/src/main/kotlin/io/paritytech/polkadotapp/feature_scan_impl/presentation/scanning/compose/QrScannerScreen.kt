package io.paritytech.polkadotapp.feature_scan_impl.presentation.scanning.compose

import androidx.camera.compose.CameraXViewfinder
import androidx.camera.core.SurfaceRequest
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.paritytech.polkadotapp.common.utils.openAppSettings
import io.paritytech.polkadotapp.design.components.dialog.NovaAlertDialog
import io.paritytech.polkadotapp.design.components.icon.NovaIcon
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.Close
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.design.utils.collectAsEffect
import io.paritytech.polkadotapp.feature_scan_impl.R
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import io.paritytech.polkadotapp.common.R as RCommon

private val LabelOffsetFromCenter = 250.dp

/**
 * Viewfinder shared by both scanner hosts. [onCloseClick] is null in the tab host, where there is nothing to close.
 */
@Composable
internal fun QrScannerScreen(
    surfaceRequestFlow: StateFlow<SurfaceRequest?>,
    invalidCodeEvent: SharedFlow<Unit>,
    cameraPermissionDeniedFlow: StateFlow<Boolean>,
    bindToCamera: suspend (LifecycleOwner) -> Unit,
    onInvalidCodeAlertClosed: () -> Unit,
    onPermissionAlertClosed: () -> Unit,
    onCloseClick: (() -> Unit)?
) {
    val owner = LocalLifecycleOwner.current
    LaunchedEffect(owner) {
        bindToCamera(owner)
    }

    Box(
        modifier = Modifier.fillMaxSize()
    ) {
        val surfaceRequest by surfaceRequestFlow.collectAsStateWithLifecycle()
        surfaceRequest?.let {
            CameraXViewfinder(
                modifier = Modifier.fillMaxSize(),
                surfaceRequest = it
            )
        }

        Image(
            modifier = Modifier.fillMaxSize(),
            painter = painterResource(R.drawable.img_scanner_frame),
            contentScale = ContentScale.Crop,
            contentDescription = "image_overlay"
        )

        NovaText(
            modifier = Modifier
                .align(Alignment.Center)
                .offset(y = LabelOffsetFromCenter)
                .padding(horizontal = PolkadotTheme.spacings.extraLargeIncreased),
            text = stringResource(RCommon.string.scan_point_camera_at_qr_code),
            color = PolkadotTheme.colors.fg.staticWhite,
            style = PolkadotTheme.typography.title.medium,
            textAlign = TextAlign.Center
        )

        if (onCloseClick != null) {
            IconButton(
                modifier = Modifier
                    .systemBarsPadding()
                    .padding(
                        horizontal = PolkadotTheme.spacings.small,
                        vertical = PolkadotTheme.spacings.smallIncreased
                    ),
                onClick = onCloseClick
            ) {
                NovaIcon(
                    imageVector = NovaIcons.Close,
                    tint = PolkadotTheme.colors.fg.staticWhite
                )
            }
        }
    }

    var invalidQrAlertIsVisible by remember { mutableStateOf(false) }
    invalidCodeEvent.collectAsEffect { _, _ ->
        invalidQrAlertIsVisible = true
    }

    if (invalidQrAlertIsVisible) {
        NovaAlertDialog(
            title = stringResource(RCommon.string.scan_invalid_code_error_title),
            text = stringResource(RCommon.string.scan_invalid_code_error_message),
            positiveButtonTitle = stringResource(RCommon.string.scan_invalid_code_error_action),
            onPositiveButtonClick = {
                invalidQrAlertIsVisible = false
                onInvalidCodeAlertClosed()
            },
            onDismissRequest = {
                invalidQrAlertIsVisible = false
                onInvalidCodeAlertClosed()
            }
        )
    }

    val cameraPermissionDenied by cameraPermissionDeniedFlow.collectAsStateWithLifecycle()
    if (cameraPermissionDenied) {
        val context = LocalContext.current

        NovaAlertDialog(
            title = stringResource(RCommon.string.common_permission_permissions_denied_title),
            text = stringResource(RCommon.string.common_permission_permissions_denied_message),
            positiveButtonTitle = stringResource(RCommon.string.common_to_settings),
            onPositiveButtonClick = {
                onPermissionAlertClosed()
                context.openAppSettings()
            },
            negativeButtonTitle = stringResource(RCommon.string.common_cancel),
            onNegativeButtonClick = onPermissionAlertClosed,
            onDismissRequest = onPermissionAlertClosed
        )
    }
}
