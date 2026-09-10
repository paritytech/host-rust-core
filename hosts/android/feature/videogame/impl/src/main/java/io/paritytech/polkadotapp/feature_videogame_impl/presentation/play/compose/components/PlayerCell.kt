package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.*
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.layout
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.PopupProperties
import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.design.components.icon.NovaIcon
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.VisibilityOffOutlined
import io.paritytech.polkadotapp.design.components.icon.vectors.VisibilityOnFilled
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.components.tooltip.PolkadotTooltip
import io.paritytech.polkadotapp.design.components.tooltip.TooltipAlignment
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.webrtc.PlayerConnectionState
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.components.icons.CloudTooltipShape
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.components.icons.FrontHand
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.components.icons.WavingHand
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.theme.GameColors
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.icons.SelectionNegative
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.icons.SelectionPositive
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.models.PlayerUiModel
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.models.VideoGameUiState
import kotlinx.coroutines.launch
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
internal fun PlayerCell(
    modifier: Modifier,
    state: VideoGameUiState,
    player: PlayerUiModel,
    onClick: () -> Unit,
    isSelected: Boolean,
    onBanToggle: () -> Unit,
    sugarLevel: Float = 0f
) {
    val selectionState = selectionState(player, isSelected, state)
    val selectionEnabled = player.isSelectable

    var haloKey by remember { mutableIntStateOf(0) }

    Box(modifier) {
        HaloOverlay(
            modifier = Modifier
                .matchParentSize()
                .haloBleed(HALO_BLEED),
            playKey = haloKey,
        )

        AnimatedPlayerFrame(
            modifier = Modifier.fillMaxSize(),
            role = player.frameRole(),
            mode = state.frameMode()
        ) {
            PolkadotSurface(
                modifier = Modifier.fillMaxSize(),
                color = GameColors.playerFrameBackground,
                shape = PlayerFrameContentShape,
                onClick = onClick,
                border = selectionState.toBorderStroke(),
                enabled = selectionEnabled
            ) {
                if (player.isBanned) {
                    BannedOverlay()
                } else {
                    player.videoTrack?.Render(
                        modifier = Modifier.fillMaxSize(),
                        isMirrored = player.isCurrentPlayer
                    )

                    SelectionOverlay(selectionState)

                    if (sugarLevel > 0f) {
                        ConfettiOverlay(
                            modifier = Modifier.fillMaxSize(),
                            sugarLevel = sugarLevel,
                            onFinale = { haloKey++ },
                        )
                    }

                    val playerDisconnected = player.connection != PlayerConnectionState.Connected
                    if (player.isCurrentPlayer.not() && playerDisconnected) {
                        WhiteNoiseIcon(modifier = Modifier.fillMaxSize())
                    }
                }
            }
        }

        if (player.isBanned || (player.isCurrentPlayer.not() && player.connection == PlayerConnectionState.Connected)) {
            BanToggleButton(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(10.dp)
                    .size(32.dp),
                isBanned = player.isBanned,
                onClick = onBanToggle
            )
        }

        GestureHintTooltip(
            show = player.showGestureHintTooltip,
            isCurrentPlayer = player.isCurrentPlayer
        )
    }
}

@Composable
private fun BanToggleButton(
    modifier: Modifier = Modifier,
    isBanned: Boolean,
    onClick: () -> Unit
) {
    val backgroundColor = if (isBanned) GameColors.banToggleBannedBg else GameColors.banToggleActiveBg
    val icon = if (isBanned) NovaIcons.VisibilityOnFilled else NovaIcons.VisibilityOffOutlined

    PolkadotSurface(
        modifier = modifier,
        shape = PolkadotTheme.shapes.full,
        color = backgroundColor,
        onClick = onClick
    ) {
        NovaIcon(
            modifier = Modifier
                .align(Alignment.Center)
                .padding(PolkadotTheme.spacings.small),
            imageVector = icon,
            tint = PolkadotTheme.colors.fg.staticWhite
        )
    }
}

@Composable
private fun GestureHintTooltip(
    show: Boolean,
    isCurrentPlayer: Boolean,
) {
    PolkadotTooltip(
        expanded = show,
        onDismiss = { },
        shape = CloudTooltipShape,
        arrowVisible = true,
        alignment = TooltipAlignment.Top,
        properties = PopupProperties(focusable = false),
    ) {
        Row(
            modifier = Modifier.padding(
                horizontal = 20.dp,
                vertical = PolkadotTheme.spacings.extraMedium
            ),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(PolkadotTheme.spacings.small)
        ) {
            NovaIcon(
                imageVector = if (isCurrentPlayer) NovaIcons.WavingHand else NovaIcons.FrontHand,
                tint = PolkadotTheme.colors.fg.primaryInverted,
            )

            NovaText(
                text = stringResource(
                    if (isCurrentPlayer) {
                        RCommon.string.video_game_tips_show_gesture
                    } else {
                        RCommon.string.video_game_tips_copy_host
                    }
                ),
                style = PolkadotTheme.typography.title.medium,
                color = PolkadotTheme.colors.fg.primaryInverted,
                softWrap = false,
                maxLines = 1,
            )
        }
    }
}

@Composable
private fun SelectionOverlay(selectionState: SelectionState) {
    val visible = selectionState != SelectionState.NONE
    val displayedState = remember { mutableStateOf(selectionState) }
    if (visible) displayedState.value = selectionState

    AnimatedVisibility(
        visible = visible,
        enter = fadeIn(),
        exit = fadeOut()
    ) {
        SelectionOverlayContent(displayedState.value)
    }
}

@Composable
private fun SelectionOverlayContent(state: SelectionState) {
    val selectionIcon = state.icon
    val springScale = remember { Animatable(0.2f) }
    val springAlpha = remember { Animatable(0f) }

    LaunchedEffect(state) {
        springScale.snapTo(0.2f)
        springAlpha.snapTo(0f)
        launch {
            springScale.animateTo(
                targetValue = 1f,
                animationSpec = spring(dampingRatio = 0.7f, stiffness = 250f)
            )
        }
        launch {
            springAlpha.animateTo(
                targetValue = 1f,
                animationSpec = tween(450)
            )
        }
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(state.color.copy(alpha = 0.3f)),
        contentAlignment = Alignment.Center
    ) {
        selectionIcon?.let {
            Image(
                modifier = Modifier
                    .size(112.dp)
                    .graphicsLayer {
                        scaleX = springScale.value
                        scaleY = springScale.value
                        alpha = springAlpha.value
                    },
                imageVector = it,
                contentDescription = null
            )
        }
    }
}

private fun selectionState(
    player: PlayerUiModel,
    isSelected: Boolean,
    state: VideoGameUiState
) = when {
    state !is VideoGameUiState.Hosting -> SelectionState.NONE
    player.isSelectable.not() -> SelectionState.NONE
    isSelected -> SelectionState.POSITIVE
    state.isEnding -> SelectionState.NEGATIVE
    else -> SelectionState.NONE
}

private val HALO_BLEED = 58.dp

private fun Modifier.haloBleed(bleed: Dp) = layout { measurable, constraints ->
    val bleedPx = bleed.roundToPx()
    val expanded = constraints.copy(
        minWidth = constraints.maxWidth + bleedPx * 2,
        maxWidth = constraints.maxWidth + bleedPx * 2,
        minHeight = constraints.maxHeight + bleedPx * 2,
        maxHeight = constraints.maxHeight + bleedPx * 2,
    )
    val placeable = measurable.measure(expanded)
    layout(constraints.maxWidth, constraints.maxHeight) {
        placeable.place(-bleedPx, -bleedPx)
    }
}

private enum class SelectionState(
    val color: Color,
    val borderWidth: Dp,
    val icon: ImageVector? = null
) {
    NONE(Color.Transparent, 0.dp),
    POSITIVE(GameColors.selectionPositive, 6.dp, SelectionPositive),
    NEGATIVE(GameColors.selectionNegative, 6.dp, SelectionNegative);

    fun toBorderStroke(): BorderStroke? = when (this) {
        NONE -> null
        else -> BorderStroke(borderWidth, color)
    }
}

@Preview
@Composable
private fun PlayerCellPreview() {
    PolkadotTheme {
        PlayerCell(
            modifier = Modifier.size(200.dp),
            state = VideoGameUiState.HostIntroduction,
            player = PlayerUiModel(
                accountId = DataByteArray.empty(),
                videoTrack = null,
                connection = PlayerConnectionState.Disconnected,
                isHost = false,
                isCurrentPlayer = true,
                showGestureHintTooltip = false,
                isBanned = false,
                isSelectable = false,
            ),
            onClick = {},
            isSelected = false,
            onBanToggle = {}
        )
    }
}
