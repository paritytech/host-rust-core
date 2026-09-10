package io.paritytech.polkadotapp.feature_scan_impl.presentation.scanTab.compose

import androidx.compose.runtime.Composable
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import io.paritytech.polkadotapp.design.utils.collectAsEffect
import io.paritytech.polkadotapp.feature_scan_impl.presentation.scanTab.ScanTabViewModel
import io.paritytech.polkadotapp.feature_scan_impl.presentation.scanning.compose.QrScannerScreen

@Composable
fun ScanTabScreen(onLeaveScanTab: (navigate: (() -> Unit)?) -> Unit) {
    val viewModel = hiltViewModel<ScanTabViewModel>()

    viewModel.leaveScanTab.collectAsEffect { _, navigate ->
        onLeaveScanTab(navigate)
    }

    QrScannerScreen(
        surfaceRequestFlow = viewModel.surfaceRequest,
        invalidCodeEvent = viewModel.invalidCodeEvent,
        cameraPermissionDeniedFlow = viewModel.cameraPermissionDenied,
        bindToCamera = viewModel::bindToCamera,
        onInvalidCodeAlertClosed = viewModel::invalidationDialogClosed,
        onPermissionAlertClosed = viewModel::permissionAlertClosed,
        onCloseClick = null
    )
}
