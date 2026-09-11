package io.paritytech.polkadotapp.feature_settings_impl.presentation.main.components.privacyMode

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.util.lerp
import io.paritytech.polkadotapp.design.components.icon.NovaIcon
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.ShieldOutlined
import io.paritytech.polkadotapp.design.components.spacer.HorizontalSpacer
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_coinage_api.domain.recycling.RecyclingStrategyType
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.toImmutableList
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.roundToInt
import io.paritytech.polkadotapp.common.R as RCommon

/**
 * The primary operating-mode control of the payment system: how much of what the user receives is held back
 * to gain privacy before it can be spent again.
 *
 * The selected mode is a raised circle on the track, moved either by tapping a mode or by dragging it, in
 * which case it snaps to the nearest one on release. The track carries intermediate units between the three
 * presets: the underlying model is continuous in two parameters, so the positions between presets are the
 * ones a later release opens up.
 *
 * Quota is deliberately absent from the copy — it is managed automatically and the user cannot act on it.
 */
@Composable
fun PaymentPrivacyModeSelector(
    modifier: Modifier = Modifier,
    shape: Shape,
    selectedMode: RecyclingStrategyType,
    onModeSelected: (RecyclingStrategyType) -> Unit
) {
    PolkadotSurface(
        modifier = modifier,
        shape = shape,
        color = PolkadotTheme.colors.bg.surface.container
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(PolkadotTheme.spacings.mediumIncreased)
        ) {
            Header()

            VerticalSpacer { small }

            ModeSelector(
                selectedMode = selectedMode,
                onModeSelected = onModeSelected
            )
        }
    }
}

@Composable
private fun Header() {
    Row(verticalAlignment = Alignment.CenterVertically) {
        NovaIcon(
            modifier = Modifier.size(HEADER_ICON_SIZE),
            imageVector = NovaIcons.ShieldOutlined,
            tint = PolkadotTheme.colors.fg.secondary
        )

        HorizontalSpacer { small }

        NovaText(
            text = stringResource(RCommon.string.payment_privacy_mode_title),
            style = PolkadotTheme.typography.title.small,
            color = PolkadotTheme.colors.fg.primary
        )
    }
}

@Composable
private fun ModeSelector(
    selectedMode: RecyclingStrategyType,
    onModeSelected: (RecyclingStrategyType) -> Unit
) {
    val modes = RecyclingStrategyType.entries
    val appearances = modes.map { it.appearance() }.toImmutableList()
    val selectedIndex = modes.indexOf(selectedMode)

    val scope = rememberCoroutineScope()
    // Position is held as a fractional mode index rather than pixels, so it is already correct on the first
    // frame — before the row has been measured and a pixel anchor could be known.
    val position = remember { Animatable(selectedIndex.toFloat()) }
    var isDragging by remember { mutableStateOf(false) }
    var trackWidth by remember { mutableIntStateOf(0) }

    val interactionSources = remember { List(modes.size) { MutableInteractionSource() }.toImmutableList() }

    // How long a crossing's cross-fades run. Written on every pointer sample and read only when a
    // crossing starts one, so it is deliberately kept out of the snapshot system: an observable value here
    // would recompose the selector on every sample of every drag without changing anything on screen.
    val dragFade = remember { DragFade() }

    val haptics = LocalHapticFeedback.current
    // The mark the dragged circle was last over. Held across drag events so a tick fires on crossing one,
    // not on every pointer sample.
    var lastMarkIndex by remember { mutableIntStateOf(0) }

    // A dragged circle spends most of the gesture between two modes; this is the one it is closest to.
    val nearestIndex by remember {
        derivedStateOf { position.value.roundToInt().coerceIn(modes.indices) }
    }

    // Outside a drag the selected mode is the truth; only while a finger is down does the nearest one lead,
    // so the circles, markers and labels follow the dragged circle rather than the mode still committed.
    val highlightedIndex = if (isDragging) nearestIndex else selectedIndex

    // A tap never slides the selection along the track: the position jumps, and the two circles animate
    // their own size in place. Only a drag moves a circle, which is what keeps `position` continuous.
    LaunchedEffect(selectedIndex) {
        if (!isDragging) {
            position.snapTo(selectedIndex.toFloat())
        }
    }

    Column {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(CIRCLE_BOX_SIZE)
                .onSizeChanged { trackWidth = it.width }
        ) {
            // The visuals carry no semantics of their own; the touch targets below describe each mode in one
            // node, so a screen reader reads a mode once rather than as three loose fragments.
            Box(modifier = Modifier.clearAndSetSemantics { }) {
                PrivacyModeTrack(
                    modifier = Modifier
                        .align(Alignment.Center)
                        .fillMaxWidth()
                        .height(TRACK_HEIGHT)
                )

                modes.indices.forEach { index ->
                    // While a drag is in flight the circle under the finger is the dragged one below, so the
                    // mode it currently covers hands its place over: it dissolves under that circle and
                    // fades back in as the circle leaves, rather than blinking out and back.
                    // It stays grown the whole time it is covered, because the drag ends by removing the
                    // circle above it: anything left to animate then plays out in plain sight.
                    val isCovered = isDragging && index == highlightedIndex
                    val reveal = remember { Animatable(1f) }

                    LaunchedEffect(isCovered, isDragging) {
                        when {
                            // Going covered and coming out of a drag are both handovers with the dragged
                            // circle: it appears or disappears in a single frame, so anything gradual here
                            // would show through as a flicker beside it.
                            !isDragging -> reveal.snapTo(1f)
                            isCovered -> reveal.snapTo(0f)
                            else -> reveal.animateTo(1f, tween(dragFade.millis, easing = LinearEasing))
                        }
                    }

                    ModeCircle(
                        modifier = Modifier
                            .align(Alignment.CenterStart)
                            .offset(centreOffset({ index.toFloat() }, { trackWidth }, modes.lastIndex))
                            // The animation above only reaches the value a frame after the composition that
                            // asked for it, which is one frame too late for a handover; the two settled
                            // cases are therefore stated here, where they hold from the first frame.
                            .graphicsLayer {
                                alpha = when {
                                    !isDragging -> 1f
                                    isCovered -> 0f
                                    else -> reveal.value
                                }
                            },
                        appearance = appearances[index],
                        isSelected = index == highlightedIndex,
                        // A mode lights up once the selection has settled on it, so nothing glows while a
                        // finger is still choosing.
                        hasGlow = !isDragging && index == selectedIndex,
                        fadeMillis = { dragFade.millis },
                        interactionSource = interactionSources[index]
                    )
                }

                if (isDragging) {
                    ModeCircle(
                        modifier = Modifier
                            .align(Alignment.CenterStart)
                            .offset(centreOffset({ position.value }, { trackWidth }, modes.lastIndex)),
                        appearance = appearances[nearestIndex],
                        isSelected = true,
                        hasGlow = false,
                        fadeMillis = { dragFade.millis },
                        interactionSource = interactionSources[nearestIndex]
                    )
                }
            }

            // The drag lives on the parent of the touch targets: a tap never crosses the slop, so it reaches
            // the cell below, and once a drag starts the cell's own click is cancelled.
            Row(
                modifier = Modifier
                    .matchParentSize()
                    .selectableGroup()
                    .pointerInput(modes.size) {
                        detectHorizontalDragGestures(
                            onDragStart = {
                                isDragging = true
                                dragFade.millis = SLOW_DRAG_FADE_MILLIS
                                lastMarkIndex = markIndexOf(position.value, size.width, TRACK_INSET.toPx(), TICK_STEP.toPx(), modes.lastIndex)
                            },
                            onDragCancel = {
                                scope.launch {
                                    position.animateTo(selectedIndex.toFloat(), SELECTION_ANIMATION)
                                    isDragging = false
                                }
                            },
                            onDragEnd = {
                                val nearest = position.value.roundToInt().coerceIn(modes.indices)
                                if (modes[nearest] != selectedMode) {
                                    haptics.performHapticFeedback(HapticFeedbackType.Confirm)
                                }
                                onModeSelected(modes[nearest])

                                // The flag drops only after the circle has arrived, so the dragged circle
                                // hands over to the static one exactly where it came to rest.
                                scope.launch {
                                    position.animateTo(nearest.toFloat(), SELECTION_ANIMATION)
                                    isDragging = false
                                }
                            },
                            onHorizontalDrag = { change, dragAmount ->
                                change.consume()

                                val step = trackStep(size.width, TRACK_INSET.toPx(), modes.lastIndex)
                                if (step > 0f) {
                                    val elapsed = change.uptimeMillis - change.previousUptimeMillis
                                    dragFade.observe(dragAmount, step, elapsed)

                                    val dragged = (change.position.x - TRACK_INSET.toPx()) / step
                                    val clamped = dragged.coerceIn(0f, modes.lastIndex.toFloat())

                                    val mark = markIndexOf(
                                        clamped,
                                        size.width,
                                        TRACK_INSET.toPx(),
                                        TICK_STEP.toPx(),
                                        modes.lastIndex
                                    )
                                    if (mark != lastMarkIndex) {
                                        lastMarkIndex = mark
                                        haptics.performHapticFeedback(HapticFeedbackType.SegmentFrequentTick)
                                    }

                                    scope.launch { position.snapTo(clamped) }
                                }
                            }
                        )
                    }
            ) {
                modes.forEachIndexed { index, mode ->
                    ModeTouchTarget(
                        appearance = appearances[index],
                        isSelected = mode == selectedMode,
                        interactionSource = interactionSources[index],
                        onClick = {
                            if (mode != selectedMode) {
                                haptics.performHapticFeedback(HapticFeedbackType.Confirm)
                            }
                            onModeSelected(mode)
                        }
                    )
                }
            }
        }

        ModeMarkers(
            appearances = appearances,
            nearestIndex = { highlightedIndex },
            trackWidth = { trackWidth }
        )

        ModeLabels(appearances = appearances, highlightedIndex = highlightedIndex)

        VerticalSpacer { small }

        SelectedModeDescription(appearance = appearances[highlightedIndex])
    }
}

// Modes are pinned centre-to-centre: half a selected circle of inset at each end, then an equal step between
// neighbours. [position] is a fractional mode index, so the selection tracks a finger continuously.
private fun centreOffset(
    position: () -> Float,
    trackWidth: () -> Int,
    lastIndex: Int
): Density.() -> IntOffset = {
    val inset = TRACK_INSET.toPx()
    val centre = inset + position() * trackStep(trackWidth(), inset, lastIndex)

    IntOffset(x = (centre - CIRCLE_BOX_SIZE.toPx() / 2f).roundToInt(), y = 0)
}

private fun trackStep(trackWidth: Int, inset: Float, lastIndex: Int): Float {
    val span = trackWidth - inset * 2f

    return if (span > 0f && lastIndex > 0) span / lastIndex else 0f
}

// Which scale mark the circle currently sits over, counted from the left end of the scale.
private fun markIndexOf(
    position: Float,
    trackWidth: Int,
    inset: Float,
    markStep: Float,
    lastIndex: Int
): Int {
    val offsetFromScaleStart = position * trackStep(trackWidth, inset, lastIndex)

    return if (markStep > 0f) floor(offsetFromScaleStart / markStep).toInt() else 0
}

@Composable
private fun ModeMarkers(
    appearances: ImmutableList<ModeAppearance>,
    nearestIndex: () -> Int,
    trackWidth: () -> Int
) {
    Box(modifier = Modifier.fillMaxWidth().height(MARKER_BOX_SIZE)) {
        appearances.forEachIndexed { index, appearance ->
            ModeMarker(
                modifier = Modifier
                    .align(Alignment.CenterStart)
                    .offset {
                        val inset = TRACK_INSET.toPx()
                        val centre = inset + index * trackStep(trackWidth(), inset, appearances.lastIndex)

                        IntOffset(x = (centre - MARKER_BOX_SIZE.toPx() / 2f).roundToInt(), y = 0)
                    },
                appearance = appearance,
                isSelected = index == nearestIndex()
            )
        }
    }
}

// The cross-fades a crossing starts run for as long as the gesture that triggered them warrants: a flick
// must not leave the previous glyph hanging behind the finger, while a slow drag has room for a gentler
// dissolve. Both ends stay well clear of the instant swap this replaces.
private class DragFade {
    var millis: Int = SLOW_DRAG_FADE_MILLIS

    fun observe(dragAmount: Float, step: Float, elapsedMillis: Long) {
        val speed = abs(dragAmount) / step * MILLIS_IN_SECOND / elapsedMillis.coerceAtLeast(1L)
        val fraction = (speed / FAST_DRAG_SPEED).coerceIn(0f, 1f)

        // A single pointer sample is jittery; the fade should follow the gesture, not one frame of it.
        millis = lerp(millis, lerp(SLOW_DRAG_FADE_MILLIS, FAST_DRAG_FADE_MILLIS, fraction), FADE_SMOOTHING)
    }
}

private const val SLOW_DRAG_FADE_MILLIS = 280
private const val FAST_DRAG_FADE_MILLIS = 140

// Mode widths per second at which the fade reaches its shortest.
private const val FAST_DRAG_SPEED = 3f

private const val FADE_SMOOTHING = 0.4f
private const val MILLIS_IN_SECOND = 1000f

private val HEADER_ICON_SIZE = 24.dp

private val DESCRIPTION_RADIUS = 12.dp

@Preview
@Composable
private fun PaymentPrivacyModeSelectorPreview() {
    PolkadotTheme {
        Column(
            modifier = Modifier.padding(PolkadotTheme.spacings.mediumIncreased)
        ) {
            RecyclingStrategyType.entries.forEach { mode ->
                PaymentPrivacyModeSelector(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(PolkadotTheme.radii.large),
                    selectedMode = mode,
                    onModeSelected = {}
                )

                VerticalSpacer { mediumIncreased }
            }
        }
    }
}
