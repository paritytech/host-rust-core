package io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.digitalDollar.holdings

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.tooling.preview.Preview
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.models.CoinageCompositionUiModel

/**
 * The balance partition drawn to scale: Ready, then Clearing.
 *
 * The two segments are the same two buckets as the figures below, in the same order and with the same
 * fills as the legend swatches — which is why the bar carries no labels of its own. Widths are
 * value-weighted shares of the total, and the last segment absorbs the rounding remainder so the fills
 * always meet the frame exactly. With nothing held, only the capsule frame is drawn.
 *
 * The caller sizes it: the modifier passed in is used as given rather than appended to.
 */
@Composable
internal fun CoinageCompositionBar(
    modifier: Modifier = Modifier,
    composition: CoinageCompositionUiModel,
    colors: HoldingColors,
) {
    Box(modifier = modifier) {
        PolkadotSurface(
            modifier = Modifier
                .padding(vertical = HoldingGeometry.summaryBarVerticalPadding)
                .fillMaxSize(),
            shape = RoundedCornerShape(percent = CAPSULE_PERCENT),
            // The segments are the fill; the surface contributes the frame and the clip that keeps the
            // segments inside it. Transparent is also exactly right for the empty state.
            color = Color.Transparent,
            border = BorderStroke(HoldingGeometry.frameWidth, colors.frame)
        ) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .drawWithCache {
                        val readyRight = composition.readyFraction * size.width
                        val period = HoldingGeometry.stripeWidth.toPx() * STRIPE_PERIODS_PER_WIDTH

                        onDrawBehind {
                            if (composition.isEmpty) return@onDrawBehind

                            drawRect(
                                color = colors.spendable,
                                topLeft = Offset.Zero,
                                size = Size(readyRight, size.height)
                            )

                            // Runs to the far edge rather than to its own fraction: two floats need not sum
                            // to exactly one, and a hairline of ground showing through at the end would read
                            // as a third segment.
                            drawBarberPole(
                                left = readyRight,
                                top = 0f,
                                width = size.width - readyRight,
                                height = size.height,
                                cornerRadius = 0f,
                                stripePeriod = period,
                                phase = 0f,
                                colors = colors
                            )
                        }
                    }
            )
        }
    }
}

/** One legend swatch, drawn with the same fills as the bar's segments so the two cannot drift. */
@Composable
internal fun CoinageLegendSwatch(
    fill: Color?,
    clearing: Boolean,
    colors: HoldingColors,
) {
    Box(
        modifier = Modifier
            .size(HoldingGeometry.legendSwatch)
            .drawWithCache {
                val corner = HoldingGeometry.legendSwatchCorner.toPx()
                val frame = HoldingGeometry.frameWidth.toPx()
                val period = HoldingGeometry.stripeWidth.toPx() * STRIPE_PERIODS_PER_WIDTH

                onDrawBehind {
                    if (clearing) {
                        drawBarberPole(
                            left = 0f,
                            top = 0f,
                            width = size.width,
                            height = size.height,
                            cornerRadius = corner,
                            stripePeriod = period,
                            phase = 0f,
                            colors = colors
                        )
                    }

                    drawFramedBar(
                        left = 0f,
                        top = 0f,
                        width = size.width,
                        height = size.height,
                        fill = if (clearing) Color.Transparent else fill ?: Color.Transparent,
                        frame = colors.frame,
                        frameWidth = frame,
                        cornerRadius = corner
                    )
                }
            }
    )
}

@Preview
@Composable
private fun CoinageCompositionBarPreview() {
    PolkadotTheme {
        CoinageCompositionBar(
            modifier = Modifier.height(HoldingGeometry.summaryBarHeight),
            composition = CoinageCompositionUiModel(
                readyFraction = 0.6f,
                clearingFraction = 0.4f
            ),
            colors = rememberHoldingColors()
        )
    }
}

private const val CAPSULE_PERCENT = 50
private const val STRIPE_PERIODS_PER_WIDTH = 2f
