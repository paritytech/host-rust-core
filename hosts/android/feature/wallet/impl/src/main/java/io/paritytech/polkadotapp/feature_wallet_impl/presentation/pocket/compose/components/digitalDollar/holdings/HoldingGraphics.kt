package io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.digitalDollar.holdings

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.State
import androidx.compose.runtime.remember
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.TileMode
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.design.theme.PolkadotTheme

/**
 * Every size the holdings marks are drawn from.
 *
 * Plain `Dp` constants rather than theme spacings, which are for paddings and margins: each value here is an
 * element size, a stroke width or a corner radius. Keeping them in one object is what makes a coin row and a
 * voucher row exactly as tall as each other, and what lets the key illustrate a mark with the drawing code
 * the list uses rather than a lookalike.
 */
internal object HoldingGeometry {
    /** The height of every mark, and so the diameter of a hop disc. */
    val markHeight = 21.dp

    /** The summary bar is its own height: it is a chart, not a mark in a row. */
    val summaryBarHeight = 20.dp
    val summaryBarVerticalPadding = 2.dp

    /** Between a coin's discs, and between a voucher's two bars. */
    val gap = 4.dp

    /**
     * Short of a capsule's 10.5, which is the point: at its minimum width the solid bar has to read as a
     * rounded square and not as another hop disc.
     */
    val solidBarCorner = 5.5.dp

    /** A near-zero score still leaves a mark, and a square one at that. */

    val frameWidth = 1.dp

    /** The unknown pair is thin enough that a full-weight frame would swallow it. */
    val unknownFrameWidth = 0.75.dp
    val unknownBarHeight = 3.dp
    val unknownBarGap = 4.dp
    val unknownPairMinWidth = 6.dp

    /** Clustered at the centre on a pitch, which is what keeps four legible inside [markHeight]. */
    val innerDotSize = 4.dp
    val innerDotCorner = 2.dp
    val innerDotPitch = 6.dp

    val overflowChipMinWidth = 26.dp
    val overflowChipHorizontalPadding = 6.dp

    val legendSwatch = 12.dp
    val legendSwatchCorner = 3.dp

    val stripeWidth = 5.dp

    /** Between the amount column and the depiction column, and between rows. */
    val detailsColumnSpacing = 12.dp
    val detailsRowSpacing = 18.dp

    /** Summary block. */
    val containerCorner = 24.dp
    val containerPadding = 16.dp
    val containerSpacing = 12.dp
    val headlineSpacing = 4.dp
    val legendColumnSpacing = 8.dp
    val legendRowSpacing = 4.dp
    val legendSwatchLabelSpacing = 6.dp

    /** The key panel. */
    val keyPanelCorner = 12.dp
    val keyPanelPadding = 12.dp
    val keyEntrySpacing = 16.dp
    val keyIllustrationWidth = 56.dp
    val keyIllustrationSpacing = 12.dp
}

/**
 * The colours the holdings marks are drawn in.
 *
 * The division is the load-bearing rule. A *pinned* colour carries status and is the same on every theme:
 * `fg.error` is #D9363E and `bg.status.warning` is #F59E0B on all five, so "spendable" cannot change colour
 * underneath the reader. Reaching for a theme-following token here would destroy the meaning — `fg.primary`
 * runs from #F4F4F5 on BerlinNight to #431407 on Lisbon.
 *
 * `bg.status.warning` rather than `fg.warning` for the same reason: `fg.warning` splits, #F59E0B dark against
 * #D17F00 light.
 */
@Immutable
internal data class HoldingColors(
    /** Spendable, unloadable, inner dots, and the ground the stripes sit on. */
    val spendable: Color,
    /** Not spendable, the hop disc, the stripes, and the upper unknown bar. */
    val notSpendable: Color,
    val unknownLower: Color,
    val chipOutline: Color,
    val chipLabel: Color,
) {
    /**
     * A literal, not a token: it has to stay dark on light surfaces and is what makes an unframed white or
     * orange mark legible at all — orange measures under 2:1 against a light surface on its own. It measures
     * 18:1 against white and 15:1 or better against every light surface here; on BerlinNight it merges into
     * the background, which costs nothing because white already measures 19:1 there.
     */
    val frame: Color = MARK_FRAME
}

@Composable
internal fun rememberHoldingColors(): HoldingColors {
    val spendable = PolkadotTheme.colors.fg.staticWhite
    val notSpendable = PolkadotTheme.colors.fg.error
    val unknownLower = PolkadotTheme.colors.bg.status.warning
    val chipOutline = PolkadotTheme.colors.stroke.tertiary
    val chipLabel = PolkadotTheme.colors.fg.secondary

    return remember(spendable, notSpendable, unknownLower, chipOutline, chipLabel) {
        HoldingColors(
            spendable = spendable,
            notSpendable = notSpendable,
            unknownLower = unknownLower,
            chipOutline = chipOutline,
            chipLabel = chipLabel,
        )
    }
}

/**
 * One clock for every moving barber pole on screen — the voucher rows and the key — so they cannot drift
 * apart.
 */
@Composable
internal fun rememberBarberPolePhase(): State<Float> =
    rememberInfiniteTransition(label = "barberPole").animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(STRIPE_CYCLE_MILLIS, easing = LinearEasing),
            repeatMode = RepeatMode.Restart
        ),
        label = "barberPolePhase"
    )

/** Fill plus a frame inset by half its width, so the stroke sits inside the mark rather than straddling it. */
internal fun DrawScope.drawFramedBar(
    left: Float,
    top: Float,
    width: Float,
    height: Float,
    fill: Color,
    frame: Color,
    frameWidth: Float,
    cornerRadius: Float,
) {
    if (width <= 0f) return

    val corner = CornerRadius(cornerRadius, cornerRadius)

    drawRoundRect(color = fill, topLeft = Offset(left, top), size = Size(width, height), cornerRadius = corner)

    if (width <= frameWidth || height <= frameWidth) return

    val inset = frameWidth / 2
    drawRoundRect(
        color = frame,
        topLeft = Offset(left + inset, top + inset),
        size = Size(width - frameWidth, height - frameWidth),
        cornerRadius = corner,
        style = Stroke(width = frameWidth)
    )
}

/**
 * Diagonal stripes sliding leftwards, drawn as one repeating gradient rather than a stack of paths.
 *
 * The gradient axis runs perpendicular to the stripes, so a lean of [STRIPE_LEAN] horizontal per unit of
 * height puts the stripes along `(lean, 1)` and the axis along `(1, -lean)`. Its length is one whole period,
 * which is what lets the wrap be seamless: the origin slides *along that axis* by exactly one period per
 * cycle, so the pattern at phase 1 is the pattern at phase 0. Sliding it horizontally instead would project
 * onto the axis as a fraction of a period and jump the stripes on every wrap.
 *
 * The two stops meeting at [STRIPE_SPLIT] are a hair apart so the edge stays crisp without relying on the
 * renderer accepting two stops at one position.
 */
internal fun DrawScope.drawBarberPole(
    left: Float,
    top: Float,
    width: Float,
    height: Float,
    cornerRadius: Float,
    stripePeriod: Float,
    phase: Float,
    colors: HoldingColors,
) {
    if (width <= 0f) return

    val direction = Offset(1f, -STRIPE_LEAN)
    val axis = direction / direction.getDistance() * stripePeriod
    val origin = Offset(left, top) - axis * phase

    drawRoundRect(
        brush = Brush.linearGradient(
            colorStops = arrayOf(
                0f to colors.notSpendable,
                STRIPE_SPLIT to colors.notSpendable,
                STRIPE_SPLIT + STRIPE_EDGE to colors.spendable,
                1f to colors.spendable
            ),
            start = origin,
            end = origin + axis,
            tileMode = TileMode.Repeated
        ),
        topLeft = Offset(left, top),
        size = Size(width, height),
        cornerRadius = CornerRadius(cornerRadius, cornerRadius)
    )
}

/**
 * The red-over-orange pair standing for "no record exists" — an absence, never a status, which is why it has
 * only ever this one colour combination.
 *
 * Both bars are framed: without it the orange is illegible on a light surface.
 */
internal fun DrawScope.drawUnknownPair(
    left: Float,
    right: Float,
    centreY: Float,
    barHeight: Float,
    gap: Float,
    frameWidth: Float,
    colors: HoldingColors,
) {
    val width = right - left
    if (width <= 0f) return

    val radius = barHeight / 2

    drawFramedBar(
        left = left,
        top = centreY - gap / 2 - barHeight,
        width = width,
        height = barHeight,
        fill = colors.notSpendable,
        frame = colors.frame,
        frameWidth = frameWidth,
        cornerRadius = radius
    )
    drawFramedBar(
        left = left,
        top = centreY + gap / 2,
        width = width,
        height = barHeight,
        fill = colors.unknownLower,
        frame = colors.frame,
        frameWidth = frameWidth,
        cornerRadius = radius
    )
}

/**
 * One hop: a solid disc with inner dots for the coins that moved alongside it.
 *
 * Solid rather than a bright ring over a dark centre. Any red dark enough to read as a fill behind a brighter
 * ring also reads as black on a light surface, which is what retired the two-tone circle; the dark-centred
 * circle in the design file is a legend illustration drawn on a black canvas, not the row style.
 *
 * Dots cluster at the centre on a pitch rather than spreading around the edge, which is what keeps four of
 * them legible inside a 21pt disc. A single dot takes the middle, where an angle would be arbitrary.
 */
internal fun DrawScope.drawHopDisc(
    left: Float,
    top: Float,
    diameter: Float,
    dotCount: Int,
    dotSize: Float,
    dotCorner: Float,
    pitch: Float,
    colors: HoldingColors,
) {
    val radius = diameter / 2
    val centre = Offset(left + radius, top + radius)

    drawCircle(color = colors.notSpendable, radius = radius, center = centre)

    dotOffsets(dotCount, pitch).forEach { offset ->
        drawRoundRect(
            color = colors.spendable,
            topLeft = Offset(centre.x + offset.x - dotSize / 2, centre.y + offset.y - dotSize / 2),
            size = Size(dotSize, dotSize),
            cornerRadius = CornerRadius(dotCorner, dotCorner)
        )
    }
}

/**
 * Offsets from the disc centre, as multiples of half the pitch so the cluster scales with it.
 *
 * Three is not an equilateral third of a circle: it is nudged into a tighter triangle that reads as a group
 * at this size rather than as three separate marks.
 */
private fun dotOffsets(dotCount: Int, pitch: Float): List<Offset> {
    val half = pitch / 2

    return when (dotCount.coerceAtMost(MAX_INNER_DOTS)) {
        1 -> listOf(Offset.Zero)
        2 -> listOf(Offset(-half, 0f), Offset(half, 0f))
        3 -> listOf(
            Offset(0f, -TRIANGLE_TOP * half),
            Offset(-TRIANGLE_SIDE * half, TRIANGLE_BASE * half),
            Offset(TRIANGLE_SIDE * half, TRIANGLE_BASE * half)
        )
        MAX_INNER_DOTS -> listOf(
            Offset(-half, -half),
            Offset(half, -half),
            Offset(-half, half),
            Offset(half, half)
        )
        else -> emptyList()
    }
}

internal const val MAX_INNER_DOTS = 4

private val MARK_FRAME = Color(0xFF141418)

private const val STRIPE_CYCLE_MILLIS = 1800
private const val STRIPE_SPLIT = 0.5f
private const val STRIPE_EDGE = 0.001f

/** Horizontal travel per unit of height, which is what sets the stripes' slant. */
private const val STRIPE_LEAN = 0.7f

private const val TRIANGLE_TOP = 1.2f
private const val TRIANGLE_SIDE = 1.0666f
private const val TRIANGLE_BASE = 0.8f

/**
 * Runs [block] clipped to a rounded rectangle at the origin.
 *
 * `DrawTransform` offers only rectangular and path clips, so the shape is built as a path. Callers that draw
 * every frame should hold the result of [roundedBarPath] rather than rebuilding it here.
 */
internal inline fun DrawScope.clipToBar(path: Path, block: DrawScope.() -> Unit) = clipPath(path, block = block)

/** The outline of one bar, for clipping segments that must meet inside it. */
internal fun roundedBarPath(width: Float, height: Float, cornerRadius: Float): Path = Path().apply {
    addRoundRect(
        RoundRect(
            rect = Rect(Offset.Zero, Size(width, height)),
            cornerRadius = CornerRadius(cornerRadius, cornerRadius)
        )
    )
}
