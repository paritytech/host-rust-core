package io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.digitalDollar.holdings

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.unit.Dp
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.models.CoinHopUiModel
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.models.CoinageHoldingUiModel
import kotlinx.collections.immutable.ImmutableList

/**
 * A voucher's bar: how traceable it will remain even once its ring fills, then the privacy still to earn.
 *
 * One bar rather than two marks, because the two readings are parts of a single quantity and a gap between
 * them invited reading the striped part as a separate thing the voucher also has.
 *
 * [stripePhase] is read inside the draw block rather than in composition, so the animation costs a redraw
 * per frame instead of recomposing the list.
 */
@Composable
internal fun VoucherStatusGraphics(
    row: CoinageHoldingUiModel.VoucherRow,
    stripePhase: State<Float>,
    colors: HoldingColors,
) {
    val fill = if (row.canUnloadNow) colors.spendable else colors.notSpendable

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(HoldingGeometry.markHeight)
            .drawWithCache {
                val height = size.height
                val layout = voucherBarLayout(
                    columnWidth = size.width,
                    // Square at its shortest, the floor the coin's block bar already takes.
                    minWidth = height,
                    solidEnd = row.solidBarEnd,
                    poleEnd = row.barberPoleEnd
                )
                val corner = HoldingGeometry.solidBarCorner.toPx()
                val period = HoldingGeometry.stripeWidth.toPx() * STRIPE_PERIODS_PER_WIDTH
                // Built once per measure rather than per frame: the pole animates, the outline does not.
                val outline = roundedBarPath(layout.totalWidth, height, corner)

                onDrawBehind {
                    // Clipped to the bar's own outline so the segments meet edge to edge inside one shape,
                    // rather than reading as two marks that happen to touch.
                    clipToBar(outline) {
                        drawRect(color = fill, topLeft = Offset.Zero, size = Size(layout.solidWidth, height))

                        drawBarberPole(
                            left = layout.solidWidth,
                            top = 0f,
                            width = layout.poleWidth,
                            height = height,
                            cornerRadius = 0f,
                            stripePeriod = period,
                            phase = stripePhase.value,
                            colors = colors
                        )
                    }

                    drawFramedBar(
                        left = 0f,
                        top = 0f,
                        width = layout.totalWidth,
                        height = height,
                        fill = Color.Transparent,
                        frame = colors.frame,
                        frameWidth = HoldingGeometry.frameWidth.toPx(),
                        cornerRadius = corner
                    )
                }
            }
    )
}

/**
 * A coin's past: one disc per payment, oldest at the left, then whatever is not known.
 *
 * A coin that has never been paid draws a single block instead, whose length measures how traceable it is.
 * A coin that knows neither its past nor where it came from draws only the unknown pair.
 */
@Composable
internal fun CoinStatusGraphics(row: CoinageHoldingUiModel.CoinRow, colors: HoldingColors) {
    val fill = if (row.isSpendable) colors.spendable else colors.notSpendable

    BoxWithConstraints(
        modifier = Modifier
            .fillMaxWidth()
            .height(HoldingGeometry.markHeight)
    ) {
        val columnWidth = maxWidth
        val marks = coinMarkLayout(
            columnWidth = columnWidth.value,
            discDiameter = HoldingGeometry.markHeight.value,
            gap = HoldingGeometry.gap.value,
            chipMinWidth = HoldingGeometry.overflowChipMinWidth.value,
            hopCount = row.hops.size
        )

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(HoldingGeometry.markHeight)
                .drawWithCache {
                    val diameter = HoldingGeometry.markHeight.toPx()
                    val gap = HoldingGeometry.gap.toPx()
                    val centreY = size.height / 2

                    onDrawBehind {
                        val marksEnd = when {
                            row.hops.isNotEmpty() -> drawHopRun(row.hops, marks, diameter, gap, colors)

                            row.blockBarEnd != null -> {
                                val width = (row.blockBarEnd * size.width).coerceAtLeast(diameter)
                                drawFramedBar(
                                    left = 0f,
                                    top = 0f,
                                    width = width,
                                    height = diameter,
                                    fill = fill,
                                    frame = colors.frame,
                                    frameWidth = HoldingGeometry.frameWidth.toPx(),
                                    cornerRadius = HoldingGeometry.solidBarCorner.toPx()
                                )
                                size.width
                            }

                            // No past and no origin: the pair spans the whole column.
                            else -> 0f
                        }

                        val unknownLeft = if (marksEnd <= 0f) 0f else marksEnd + gap
                        if (size.width - unknownLeft >= HoldingGeometry.unknownPairMinWidth.toPx()) {
                            drawUnknownPair(
                                left = unknownLeft,
                                right = size.width,
                                centreY = centreY,
                                barHeight = HoldingGeometry.unknownBarHeight.toPx(),
                                gap = HoldingGeometry.unknownBarGap.toPx(),
                                frameWidth = HoldingGeometry.unknownFrameWidth.toPx(),
                                colors = colors
                            )
                        }
                    }
                }
        )

        if (marks.showChip) {
            OverflowChip(
                hiddenHops = marks.hiddenHops,
                colors = colors,
                offsetX = (HoldingGeometry.markHeight + HoldingGeometry.gap) * marks.discCount
            )
        }
    }
}

/** The hops that did not fit, counted rather than dropped. */
@Composable
private fun OverflowChip(hiddenHops: Int, colors: HoldingColors, offsetX: Dp) {
    PolkadotSurface(
        modifier = Modifier
            .offset(x = offsetX)
            .height(HoldingGeometry.markHeight)
            .widthIn(min = HoldingGeometry.overflowChipMinWidth),
        shape = RoundedCornerShape(percent = CAPSULE_PERCENT),
        color = Color.Transparent,
        border = BorderStroke(HoldingGeometry.frameWidth, colors.chipOutline),
        contentAlignment = Alignment.Center
    ) {
        NovaText(
            modifier = Modifier.padding(horizontal = HoldingGeometry.overflowChipHorizontalPadding),
            text = "+$hiddenHops",
            maxLines = 1,
            style = PolkadotTheme.typography.label.medium,
            color = colors.chipLabel
        )
    }
}

/** Returns the x the run of marks ends at, so the caller knows where the unknown pair may begin. */
private fun DrawScope.drawHopRun(
    hops: ImmutableList<CoinHopUiModel>,
    marks: CoinMarkLayout,
    diameter: Float,
    gap: Float,
    colors: HoldingColors,
): Float {
    var next = 0f

    repeat(marks.discCount) { index ->
        drawHopDisc(
            left = next,
            top = 0f,
            diameter = diameter,
            dotCount = hops[index].dotCount,
            dotSize = HoldingGeometry.innerDotSize.toPx(),
            dotCorner = HoldingGeometry.innerDotCorner.toPx(),
            pitch = HoldingGeometry.innerDotPitch.toPx(),
            colors = colors
        )
        next += diameter + gap
    }

    // `next` sits one gap past the last disc. The chip, when there is one, is drawn as a composable there,
    // so the run ends after it rather than after the discs.
    return if (marks.showChip) {
        next + HoldingGeometry.overflowChipMinWidth.toPx()
    } else {
        (next - gap).coerceAtLeast(0f)
    }
}

private const val CAPSULE_PERCENT = 50
private const val STRIPE_PERIODS_PER_WIDTH = 2f
