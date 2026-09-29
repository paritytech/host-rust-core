package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.photo.capture.compose

import androidx.camera.compose.CameraXViewfinder
import androidx.camera.core.SurfaceRequest
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.topbar.PolkadotTopBar
import io.paritytech.polkadotapp.design.components.topbar.TopBarTitleAlignment
import io.paritytech.polkadotapp.design.components.topbar.rememberTopBarAction
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.compose.components.icons.RecordStart
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.photo.capture.EvidencePhotoCaptureContract
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.photo.capture.compose.components.OverlayToggleButton
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.photo.capture.compose.components.TattooOverlay
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.photo.capture.models.TattooOverlayUiState
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun EvidencePhotoCaptureScreen(contract: EvidencePhotoCaptureContract) {
    val surfaceRequest by contract.surfaceRequest.collectAsStateWithLifecycle()
    val tattooOverlayState by contract.tattooOverlayUiState.collectAsStateWithLifecycle()

    val owner = LocalLifecycleOwner.current
    LaunchedEffect(Unit) {
        contract.bindToCamera(owner)
    }

    EvidencePhotoCaptureScreenInternal(
        surfaceRequest = surfaceRequest,
        tattooOverlayState = tattooOverlayState,
        takePhoto = contract::takePhoto,
        onBack = contract::back,
        toggleOverlay = contract::toggleTattooOverlay
    )
}

@Composable
private fun EvidencePhotoCaptureScreenInternal(
    surfaceRequest: SurfaceRequest?,
    tattooOverlayState: TattooOverlayUiState,
    takePhoto: () -> Unit,
    onBack: () -> Unit,
    toggleOverlay: () -> Unit
) {
    PolkadotSurface(
        modifier = Modifier.fillMaxSize()
    ) {
        Box(modifier = Modifier.fillMaxSize()) {
            surfaceRequest?.let {
                CameraXViewfinder(
                    modifier = Modifier.fillMaxSize(),
                    surfaceRequest = it
                )
            }

            Column(
                modifier = Modifier.fillMaxSize()
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .background(PolkadotTheme.colors.bg.surface.overlay)
                ) {
                    PolkadotTopBar(
                        title = stringResource(RCommon.string.evidence_photo_capture_title),
                        navigationAction = rememberTopBarAction(onBack),
                        titleAlignment = TopBarTitleAlignment.Center,
                    )
                }

                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .aspectRatio(1f)
                ) {
                    TattooOverlay(
                        modifier = Modifier.fillMaxSize(),
                        state = tattooOverlayState
                    )
                }

                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .background(PolkadotTheme.colors.bg.surface.overlay)
                        .navigationBarsPadding(),
                    verticalArrangement = Arrangement.SpaceEvenly,
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    OverlayToggleButton(
                        modifier = Modifier,
                        onClick = toggleOverlay
                    )

                    Image(
                        modifier = Modifier
                            .clip(PolkadotTheme.shapes.full)
                            .clickable(onClick = takePhoto),
                        imageVector = RecordStart,
                        contentDescription = "capture_button"
                    )
                }
            }
        }
    }
}
