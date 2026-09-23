package io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.digitalDollar

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import io.paritytech.polkadotapp.design.components.icon.NovaIcon
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.ArrowDownward
import io.paritytech.polkadotapp.design.components.icon.vectors.ArrowUpwards
import io.paritytech.polkadotapp.design.components.icon.vectors.Info
import io.paritytech.polkadotapp.design.components.spacer.HorizontalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.digitalDollar.holdings.HoldingColors
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.digitalDollar.holdings.HoldingGeometry
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.digitalDollar.holdings.clipToBar
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.digitalDollar.holdings.drawBarberPole
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.digitalDollar.holdings.drawFramedBar
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.digitalDollar.holdings.drawHopDisc
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.digitalDollar.holdings.drawUnknownPair
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.digitalDollar.holdings.roundedBarPath
import io.paritytech.polkadotapp.common.R as RCommon

/**
 * A collapsed row that explains the marks, and four illustrated entries when opened.
 *
 * Every illustration is the real drawing code at a fixed width, not a facsimile, so the key cannot end up
 * describing a mark the list has stopped drawing. Its expanded state is owned by the caller, so it outlives
 * the holdings updating underneath it.
 */
@Composable
internal fun CoinageKey(
    expanded: Boolean,
    onToggle: () -> Unit,
    colors: HoldingColors,
    stripePhase: State<Float>
) {
    Column {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(onClick = onToggle),
            verticalAlignment = Alignment.CenterVertically
        ) {
            NovaIcon(
                modifier = Modifier.size(HoldingGeometry.legendSwatch),
                imageVector = NovaIcons.Info,
                tint = PolkadotTheme.colors.fg.secondary
            )

            HorizontalSpacer { HoldingGeometry.legendSwatchLabelSpacing }

            NovaText(
                modifier = Modifier.weight(1f),
                text = stringResource(RCommon.string.pocket_coinage_key_title),
                style = PolkadotTheme.typography.body.medium,
                color = PolkadotTheme.colors.fg.secondary
            )

            NovaIcon(
                modifier = Modifier.size(HoldingGeometry.legendSwatch),
                imageVector = if (expanded) NovaIcons.ArrowUpwards else NovaIcons.ArrowDownward,
                tint = PolkadotTheme.colors.fg.secondary
            )
        }

        AnimatedVisibility(visible = expanded) {
            PolkadotSurface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(HoldingGeometry.keyPanelCorner),
                color = PolkadotTheme.colors.bg.surface.nested
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(HoldingGeometry.keyPanelPadding),
                    verticalArrangement = Arrangement.spacedBy(HoldingGeometry.keyEntrySpacing)
                ) {
                    KeyEntry(text = stringResource(RCommon.string.pocket_coinage_key_hops)) {
                        HopIllustration(colors)
                    }
                    KeyEntry(text = stringResource(RCommon.string.pocket_coinage_key_unknown)) {
                        UnknownIllustration(colors)
                    }
                    KeyEntry(text = stringResource(RCommon.string.pocket_coinage_key_block)) {
                        BlockIllustration(colors)
                    }
                    KeyEntry(text = stringResource(RCommon.string.pocket_coinage_key_voucher)) {
                        VoucherIllustration(colors, stripePhase)
                    }
                }
            }
        }
    }
}

@Composable
private fun KeyEntry(text: String, illustration: @Composable () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(
            modifier = Modifier.width(HoldingGeometry.keyIllustrationWidth),
            contentAlignment = Alignment.CenterStart
        ) {
            illustration()
        }

        HorizontalSpacer { HoldingGeometry.keyIllustrationSpacing }

        NovaText(
            modifier = Modifier.weight(1f),
            text = text,
            style = PolkadotTheme.typography.body.small,
            color = PolkadotTheme.colors.fg.secondary
        )
    }
}

/** Two discs, one carrying siblings, which is the distinction the text is about. */
@Composable
private fun HopIllustration(colors: HoldingColors) {
    Illustration { diameter, gap ->
        drawHopDisc(0f, 0f, diameter, 0, dotSize(), dotCorner(), pitch(), colors)
        drawHopDisc(diameter + gap, 0f, diameter, MAX_ILLUSTRATED_DOTS, dotSize(), dotCorner(), pitch(), colors)
    }
}

@Composable
private fun UnknownIllustration(colors: HoldingColors) {
    Illustration { _, _ ->
        drawUnknownPair(
            left = 0f,
            right = size.width,
            centreY = size.height / 2,
            barHeight = HoldingGeometry.unknownBarHeight.toPx(),
            gap = HoldingGeometry.unknownBarGap.toPx(),
            frameWidth = HoldingGeometry.unknownFrameWidth.toPx(),
            colors = colors
        )
    }
}

@Composable
private fun BlockIllustration(colors: HoldingColors) {
    Illustration { _, _ ->
        drawFramedBar(
            left = 0f,
            top = 0f,
            width = size.width,
            height = size.height,
            fill = colors.spendable,
            frame = colors.frame,
            frameWidth = HoldingGeometry.frameWidth.toPx(),
            cornerRadius = HoldingGeometry.solidBarCorner.toPx()
        )
    }
}

@Composable
private fun VoucherIllustration(colors: HoldingColors, stripePhase: State<Float>) {
    Illustration { diameter, _ ->
        val corner = HoldingGeometry.solidBarCorner.toPx()

        clipToBar(roundedBarPath(size.width, size.height, corner)) {
            drawRect(color = colors.spendable, topLeft = Offset.Zero, size = Size(diameter, size.height))

            drawBarberPole(
                left = diameter,
                top = 0f,
                width = size.width - diameter,
                height = size.height,
                cornerRadius = 0f,
                stripePeriod = HoldingGeometry.stripeWidth.toPx() * STRIPE_PERIODS_PER_WIDTH,
                phase = stripePhase.value,
                colors = colors
            )
        }

        drawFramedBar(
            left = 0f,
            top = 0f,
            width = size.width,
            height = size.height,
            fill = Color.Transparent,
            frame = colors.frame,
            frameWidth = HoldingGeometry.frameWidth.toPx(),
            cornerRadius = corner
        )
    }
}

/** One fixed-size canvas for every entry, so the illustrations line up down the panel. */
@Composable
private fun Illustration(
    draw: androidx.compose.ui.graphics.drawscope.DrawScope.(diameter: Float, gap: Float) -> Unit
) {
    Box(
        modifier = Modifier
            .width(HoldingGeometry.keyIllustrationWidth)
            .height(HoldingGeometry.markHeight)
            .drawWithCache {
                val diameter = HoldingGeometry.markHeight.toPx()
                val gap = HoldingGeometry.gap.toPx()

                onDrawBehind { draw(diameter, gap) }
            }
    )
}

private fun androidx.compose.ui.graphics.drawscope.DrawScope.dotSize() =
    HoldingGeometry.innerDotSize.toPx()

private fun androidx.compose.ui.graphics.drawscope.DrawScope.dotCorner() =
    HoldingGeometry.innerDotCorner.toPx()

private fun androidx.compose.ui.graphics.drawscope.DrawScope.pitch() =
    HoldingGeometry.innerDotPitch.toPx()

private const val MAX_ILLUSTRATED_DOTS = 3
private const val STRIPE_PERIODS_PER_WIDTH = 2f
