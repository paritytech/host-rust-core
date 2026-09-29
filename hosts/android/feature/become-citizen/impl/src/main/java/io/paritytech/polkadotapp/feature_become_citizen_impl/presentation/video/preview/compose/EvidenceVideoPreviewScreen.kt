package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.video.preview.compose

import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.media3.ui.compose.ContentFrame
import io.paritytech.polkadotapp.common.presentation.compose.video.VideoPlayerControlsContainer
import io.paritytech.polkadotapp.common.presentation.compose.video.rememberExoPlayer
import io.paritytech.polkadotapp.common.presentation.compose.video.toProgressiveMediaSource
import io.paritytech.polkadotapp.design.components.button.default.PolkadotTextButton
import io.paritytech.polkadotapp.design.components.topbar.PolkadotTopBar
import io.paritytech.polkadotapp.design.components.topbar.TopBarTitleAlignment
import io.paritytech.polkadotapp.design.components.topbar.rememberTopBarAction
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.video.preview.EvidenceVideoPreviewContract
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun EvidenceVideoPreviewScreen(contract: EvidenceVideoPreviewContract) {
    val videoUri by contract.videoUri.collectAsStateWithLifecycle()

    BackHandler {
        contract.back()
    }

    EvidenceVideoPreviewScreenInternal(
        videoUri = videoUri,
        onBack = contract::back,
        onConfirm = contract::confirm
    )
}

@Composable
private fun EvidenceVideoPreviewScreenInternal(
    videoUri: Uri?,
    onBack: () -> Unit,
    onConfirm: () -> Unit
) {
    Column(
        modifier = Modifier.fillMaxSize()
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .background(PolkadotTheme.colors.bg.surface.main)
        ) {
            PolkadotTopBar(
                title = stringResource(RCommon.string.evidence_video_preview_title),
                navigationAction = rememberTopBarAction(onBack),
                titleAlignment = TopBarTitleAlignment.Center,
            )
        }

        val context = LocalContext.current
        val mediaSource = remember(videoUri) {
            videoUri?.toProgressiveMediaSource(context)
        }
        val player = rememberExoPlayer(mediaSource = mediaSource)

        VideoPlayerControlsContainer(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(1f),
            player = player
        ) {
            ContentFrame(
                modifier = Modifier
                    .fillMaxSize()
                    .clipToBounds(),
                player = player,
                contentScale = ContentScale.Crop
            )
        }

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .background(PolkadotTheme.colors.bg.surface.main)
                .navigationBarsPadding()
        ) {
            PolkadotTextButton(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(PolkadotTheme.spacings.large)
                    .align(Alignment.BottomCenter),
                text = stringResource(RCommon.string.common_confirm),
                onClick = onConfirm
            )
        }
    }
}
