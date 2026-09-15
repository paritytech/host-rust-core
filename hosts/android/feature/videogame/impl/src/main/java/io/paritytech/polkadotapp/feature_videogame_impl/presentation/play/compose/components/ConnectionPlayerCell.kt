package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.webrtc.PlayerConnectionState
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.theme.GameColors
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.models.PlayerUiModel
import io.paritytech.polkadotapp.tools_media_connection_api.domain.models.VideoTrackEffect
import kotlinx.collections.immutable.persistentSetOf

@Composable
internal fun ConnectionPlayerCell(
    modifier: Modifier,
    player: PlayerUiModel,
    revealCamera: Boolean,
) {
    Box(modifier) {
        PolkadotSurface(
            modifier = Modifier.fillMaxSize(),
            color = GameColors.playerFrameBackground,
            shape = CellShape,
        ) {
            if (player.isBanned) {
                BannedOverlay()
            } else {
                CellContent(player, revealCamera)
            }
        }

        if (revealCamera && player.isBanned.not()) {
            ConnectionStateBadge(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .fillMaxWidth()
                    .padding(BADGE_PADDING),
                state = player.connection
            )
        }
    }
}

@Composable
private fun BoxScope.CellContent(
    player: PlayerUiModel,
    revealCamera: Boolean,
) {
    val videoTrack = player.videoTrack

    // The blur is the privacy layer over the camera; where it can't be applied (pre-S),
    // show snow rather than a sharp feed.
    val cameraVisible = revealCamera &&
        player.connection == PlayerConnectionState.Connected &&
        VideoTrackEffect.Blur.isSupported

    if (cameraVisible && videoTrack != null) {
        var firstFrameRendered by remember(videoTrack) { mutableStateOf(false) }

        videoTrack.Render(
            modifier = Modifier.fillMaxSize(),
            isMirrored = player.isCurrentPlayer,
            effects = VideoEffects,
            onFirstFrameRendered = { firstFrameRendered = true }
        )

        // Until the camera delivers its first frame the renderer is blank/grey — cover it with snow.
        if (!firstFrameRendered) {
            WhiteNoiseIcon(modifier = Modifier.matchParentSize())
        }
    } else {
        WhiteNoiseIcon(modifier = Modifier.fillMaxSize())
    }

    // Top-down scrim keeps the signal badge legible over bright video/snow.
    if (revealCamera) {
        Box(modifier = Modifier.matchParentSize().background(BadgeScrim))
    }
}

private val CellShape = RoundedCornerShape(9.dp)
private val BADGE_PADDING = 8.dp
private val VideoEffects = persistentSetOf(VideoTrackEffect.Blur)

private val BadgeScrim = Brush.verticalGradient(
    0f to GameColors.backgroundPrimary.copy(alpha = 0.88f),
    0.824f to Color.Transparent,
)

@Preview
@Composable
private fun ConnectionPlayerCellPreview() {
    PolkadotTheme {
        ConnectionPlayerCell(
            modifier = Modifier.size(200.dp),
            player = PlayerUiModel(
                accountId = DataByteArray.empty(),
                videoTrack = null,
                connection = PlayerConnectionState.Connecting,
                isHost = false,
                isCurrentPlayer = false,
                showGestureHintTooltip = false,
                isBanned = false,
                isSelectable = false,
            ),
            revealCamera = true,
        )
    }
}
