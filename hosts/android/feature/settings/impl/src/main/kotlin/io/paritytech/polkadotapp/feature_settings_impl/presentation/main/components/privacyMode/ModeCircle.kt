package io.paritytech.polkadotapp.feature_settings_impl.presentation.main.components.privacyMode

import android.graphics.BlurMaskFilter
import android.graphics.Paint
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.LocalIndication
import androidx.compose.foundation.indication
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.lerp
import io.paritytech.polkadotapp.design.components.icon.NovaIcon
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.theme.PolkadotTheme

// One mode as it sits on the track. Selecting a mode grows its circle and lights it; the mode losing the
// selection shrinks back in the same motion, so a tap reads as the selection passing between two circles
// rather than one circle travelling along the track.
// A dragged circle is a single circle that adopts each mode as it passes the midpoint towards it, so
// [appearance] changes under it mid-gesture and is cross-faded rather than swapped — see [fadeMillis].
// The glow is what says a mode has been settled on rather than merely passed over, so it is [hasGlow]'s to
// decide and not the selected size's: a circle under a finger is grown but unlit.
// The box is wider than the circle so the glow has room to spread without being clipped by the layout.
@Composable
internal fun ModeCircle(
    modifier: Modifier,
    appearance: ModeAppearance,
    isSelected: Boolean,
    hasGlow: Boolean,
    fadeMillis: () -> Int,
    interactionSource: MutableInteractionSource? = null
) {
    val selection by animateFloatAsState(
        targetValue = if (isSelected) 1f else 0f,
        animationSpec = SELECTION_ANIMATION,
        label = "circleSelection"
    )
    val glow by animateFloatAsState(
        targetValue = if (hasGlow) 1f else 0f,
        animationSpec = SELECTION_ANIMATION,
        label = "circleGlow"
    )

    // The mode the circle is coming from, held until the fade away from it completes. A crossing that
    // interrupts an unfinished fade restarts from this same mode: two crossings inside one fade would mean
    // the finger covered half a mode in under one fade, which is faster than the track allows.
    var fadeFrom by remember { mutableStateOf(appearance) }
    val fade = remember { Animatable(1f) }

    LaunchedEffect(appearance) {
        if (fadeFrom == appearance) return@LaunchedEffect

        fade.snapTo(0f)
        // Linear on purpose: two glyphs dissolving into each other with an eased curve lose ink in the
        // middle of the exchange, which reads as a blink.
        fade.animateTo(1f, tween(durationMillis = fadeMillis(), easing = LinearEasing))
        fadeFrom = appearance
    }

    // Composition sees the new mode one frame before the effect above can start the animation, so until it
    // is running the circle stays on the outgoing mode instead of flashing the incoming one.
    val progress = when {
        fadeFrom == appearance -> 1f
        fade.isRunning -> fade.value
        else -> 0f
    }
    val blended = appearance.accentBlendedFrom(fadeFrom, progress)

    val diameter = lerp(CIRCLE_SIZE, SELECTED_CIRCLE_SIZE, selection)
    val glowColor = blended.accentColor
    val shadowColor = PolkadotTheme.colors.shadow.medium

    // Held across frames and reconfigured in place: the circle's size animates, which rebuilds the draw
    // cache on every frame of a selection change, and allocating paints there would allocate per frame.
    val shadowPaint = remember { Paint().apply { isAntiAlias = true } }
    val glowPaint = remember { Paint().apply { isAntiAlias = true } }

    Box(modifier = Modifier.size(CIRCLE_BOX_SIZE).then(modifier), contentAlignment = Alignment.Center) {
        Spacer(
            modifier = Modifier
                .size(diameter)
                .drawWithCache {
                    val radius = size.minDimension / 2f
                    val centreX = size.width / 2f
                    val centreY = size.height / 2f

                    shadowPaint.color = shadowColor.copy(alpha = SHADOW_ALPHA).toArgb()
                    shadowPaint.maskFilter = BlurMaskFilter(SHADOW_BLUR.toPx(), BlurMaskFilter.Blur.NORMAL)

                    glowPaint.color = glowColor.copy(alpha = glow * GLOW_ALPHA).toArgb()
                    glowPaint.maskFilter = BlurMaskFilter(GLOW_BLUR.toPx(), BlurMaskFilter.Blur.NORMAL)

                    val shadowOffset = SHADOW_OFFSET.toPx()

                    onDrawBehind {
                        drawIntoCanvas { canvas ->
                            canvas.nativeCanvas.drawCircle(centreX, centreY + shadowOffset, radius, shadowPaint)

                            if (glow > 0f) {
                                canvas.nativeCanvas.drawCircle(centreX, centreY, radius, glowPaint)
                            }
                        }
                    }
                }
        )

        PolkadotSurface(
            modifier = Modifier.size(diameter),
            shape = CircleShape,
            brush = blended.circleBrush(selection),
            border = BorderStroke(CIRCLE_BORDER, blended.circleBorderBrush())
        ) {
            val ripple = if (interactionSource != null) {
                Modifier.indication(interactionSource, LocalIndication.current)
            } else {
                Modifier
            }

            // PolkadotSurface propagates its minimum constraints, so a size on the icon itself would be
            // clamped straight back up to the circle. This Box absorbs the minimum and lets the inset stand.
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .then(ripple),
                contentAlignment = Alignment.Center
            ) {
                val iconSize = diameter * MODE_ICON_SIZE_FRACTION

                if (progress < 1f) {
                    NovaIcon(
                        modifier = Modifier.size(iconSize).alpha(1f - progress),
                        imageVector = fadeFrom.icon,
                        tint = fadeFrom.iconColor
                    )
                }

                NovaIcon(
                    modifier = Modifier.size(iconSize).alpha(progress),
                    imageVector = appearance.icon,
                    tint = appearance.iconColor
                )
            }
        }
    }
}

internal val CIRCLE_SIZE = 28.dp
internal val SELECTED_CIRCLE_SIZE = 40.dp

private val CIRCLE_BORDER = 1.dp

private val GLOW_BLUR = 12.dp

// The glow is a halo, not a second light source: at full opacity the accent bleeds over the whole track.
internal const val GLOW_ALPHA = 0.45f

private val SHADOW_BLUR = 4.dp
private val SHADOW_OFFSET = 4.dp

// The palette's shadow colour is black at 48% and the design asks for 70% here, with nothing darker in the
// set to reach for; the token supplies the colour and this supplies the depth the design drew.
private const val SHADOW_ALPHA = 0.7f

// Selected circle plus the glow spreading either side of it.
internal val CIRCLE_BOX_SIZE = SELECTED_CIRCLE_SIZE + GLOW_BLUR * 2

// Share of the circle the glyph takes up; the rest is the inset around it.
private const val MODE_ICON_SIZE_FRACTION = 0.6f

internal val SELECTION_ANIMATION = tween<Float>(durationMillis = 200, easing = FastOutSlowInEasing)
