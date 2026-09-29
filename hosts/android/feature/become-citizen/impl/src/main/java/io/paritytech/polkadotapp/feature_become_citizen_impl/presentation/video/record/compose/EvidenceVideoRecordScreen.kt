package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.video.record.compose

import androidx.camera.compose.CameraXViewfinder
import androidx.camera.core.SurfaceRequest
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.paritytech.polkadotapp.common.presentation.formatters.time.LocalTimeFormatter
import io.paritytech.polkadotapp.design.components.progress.NovaLinearProgressIndicator
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.components.topbar.PolkadotTopBar
import io.paritytech.polkadotapp.design.components.topbar.TopBarTitleAlignment
import io.paritytech.polkadotapp.design.components.topbar.rememberTopBarAction
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.compose.components.icons.RecordStart
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.compose.components.icons.RecordStop
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.video.record.EvidenceVideoRecordContract
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.video.record.VideoFileRecorder
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun EvidenceVideoRecordScreen(contract: EvidenceVideoRecordContract) {
    val surfaceRequest by contract.surfaceRequest.collectAsStateWithLifecycle()
    val recordingState by contract.state.collectAsStateWithLifecycle()

    val owner = LocalLifecycleOwner.current
    LaunchedEffect(Unit) {
        contract.bindToCamera(owner)
    }

    EvidenceVideoRecordScreenInternal(
        surfaceRequest = surfaceRequest,
        recordingState = recordingState,
        toggleRecording = contract::toggleRecording,
        onBack = contract::back
    )
}

@Composable
private fun EvidenceVideoRecordScreenInternal(
    surfaceRequest: SurfaceRequest?,
    recordingState: VideoFileRecorder.State,
    toggleRecording: () -> Unit,
    onBack: () -> Unit
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
                        title = stringResource(RCommon.string.evidence_video_recording_title),
                        navigationAction = rememberTopBarAction(onBack),
                        titleAlignment = TopBarTitleAlignment.Center,
                    )

                    NovaLinearProgressIndicator(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(
                                horizontal = PolkadotTheme.spacings.large,
                                vertical = PolkadotTheme.spacings.mediumIncreased
                            ),
                        progress = recordingState.progress.fraction.toFloat()
                    )
                }

                Spacer(
                    modifier = Modifier
                        .fillMaxWidth()
                        .aspectRatio(1f)
                )

                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .background(PolkadotTheme.colors.bg.surface.overlay)
                        .navigationBarsPadding(),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    NovaText(
                        text = LocalTimeFormatter.current.formatTimer(recordingState.duration)
                            .takeIf { recordingState.isRecording }
                            .orEmpty(),
                        style = PolkadotTheme.typography.body.large,
                        color = PolkadotTheme.colors.fg.primary
                    )

                    VerticalSpacer { mediumIncreased }

                    Image(
                        modifier = Modifier
                            .clip(PolkadotTheme.shapes.full)
                            .clickable(onClick = toggleRecording),
                        imageVector = if (recordingState.isRecording) {
                            RecordStop
                        } else {
                            RecordStart
                        },
                        contentDescription = "recording_button"
                    )
                }
            }
        }
    }
}
