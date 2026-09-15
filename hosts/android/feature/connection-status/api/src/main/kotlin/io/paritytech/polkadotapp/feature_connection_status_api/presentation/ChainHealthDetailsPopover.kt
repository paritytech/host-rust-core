package io.paritytech.polkadotapp.feature_connection_status_api.presentation

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties
import io.paritytech.polkadotapp.design.components.spacer.HorizontalSpacer
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainConnectionPresentation
import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainMetricReading
import io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin.ChainHealthItemModel
import kotlin.time.Duration
import io.paritytech.polkadotapp.common.R as RCommon

private val POPUP_MARGIN = 12.dp
private val POPUP_GAP = 8.dp
private val POPUP_ELEVATION = 12.dp
private const val MILLIS_PER_SECOND = 1000.0

/** Tap-to-open breakdown of a single chain's connection state and per-metric readings. */
@Composable
fun ChainHealthDetailsPopover(
    expanded: Boolean,
    item: ChainHealthItemModel,
    onDismiss: () -> Unit,
) {
    if (expanded) {
        val gapPx = with(LocalDensity.current) { POPUP_GAP.roundToPx() }
        val positionProvider = remember(gapPx) { BelowAnchorPositionProvider(gapPx = gapPx) }

        Popup(
            popupPositionProvider = positionProvider,
            onDismissRequest = onDismiss,
            properties = PopupProperties(focusable = true),
        ) {
            PolkadotSurface(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = POPUP_MARGIN),
                shape = PolkadotTheme.shapes.large,
                color = PolkadotTheme.colors.bg.surface.container,
                shadowElevation = POPUP_ELEVATION,
            ) {
                Column(
                    modifier = Modifier.padding(
                        horizontal = PolkadotTheme.spacings.medium,
                        vertical = PolkadotTheme.spacings.small,
                    ),
                ) {
                    NovaText(
                        text = item.chainName,
                        style = PolkadotTheme.typography.body.mediumEmphasized,
                        color = PolkadotTheme.colors.fg.primary,
                    )
                    NovaText(
                        text = connectionLabel(item.connection),
                        style = PolkadotTheme.typography.body.small,
                        color = PolkadotTheme.colors.fg.secondary,
                    )
                    VerticalSpacer { small }
                    item.readings.forEach { reading -> ReadingRow(reading) }
                }
            }
        }
    }
}

@Composable
private fun ReadingRow(reading: ChainMetricReading) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = PolkadotTheme.spacings.extraTiny),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        NovaText(
            text = stringResource(reading.labelRes()),
            style = PolkadotTheme.typography.body.small,
            color = PolkadotTheme.colors.fg.secondary,
        )
        HorizontalSpacer { medium }
        Column(horizontalAlignment = Alignment.End) {
            NovaText(
                text = reading.actualValue(),
                style = PolkadotTheme.typography.body.small,
                color = PolkadotTheme.colors.fg.primary,
            )
            NovaText(
                text = stringResource(RCommon.string.chain_health_target, reading.targetValue()),
                style = PolkadotTheme.typography.caption.medium,
                color = PolkadotTheme.colors.fg.tertiary,
            )
        }
    }
}

@Composable
private fun connectionLabel(connection: ChainConnectionPresentation): String = stringResource(
    when (connection) {
        ChainConnectionPresentation.Connected -> RCommon.string.chain_health_connection_connected
        ChainConnectionPresentation.Connecting -> RCommon.string.chain_health_connection_connecting
        ChainConnectionPresentation.Disconnected -> RCommon.string.chain_health_connection_disconnected
    },
)

private fun ChainMetricReading.labelRes(): Int = when (this) {
    is ChainMetricReading.BlockLatency -> RCommon.string.chain_health_metric_block_latency
    is ChainMetricReading.FinalityGap -> RCommon.string.chain_health_metric_finality_gap
    is ChainMetricReading.PendingRequestLatency -> RCommon.string.chain_health_metric_pending_request
    is ChainMetricReading.ResponseLatency -> RCommon.string.chain_health_metric_response
}

@Composable
private fun ChainMetricReading.actualValue(): String = when (this) {
    is ChainMetricReading.BlockLatency -> latency.formatSeconds()
    is ChainMetricReading.FinalityGap ->
        pluralStringResource(RCommon.plurals.chain_health_blocks, gapBlocks, gapBlocks)
    is ChainMetricReading.PendingRequestLatency -> latency.formatSeconds()
    is ChainMetricReading.ResponseLatency -> latency.formatSeconds()
}

@Composable
private fun ChainMetricReading.targetValue(): String = when (this) {
    is ChainMetricReading.BlockLatency -> target.formatSeconds()
    is ChainMetricReading.FinalityGap ->
        pluralStringResource(RCommon.plurals.chain_health_blocks, targetBlocks, targetBlocks)
    is ChainMetricReading.PendingRequestLatency -> target.formatSeconds()
    is ChainMetricReading.ResponseLatency -> target.formatSeconds()
}

private fun Duration.formatSeconds(): String = "%.1fs".format(inWholeMilliseconds / MILLIS_PER_SECOND)

/**
 * Positions the popup just below the tapped anchor. The anchor already sits below the system status
 * bar, so the popup never crosses it; horizontally it is right-aligned within the window with a margin.
 */
private class BelowAnchorPositionProvider(
    private val gapPx: Int,
) : PopupPositionProvider {
    // Full-width content (margins come from the surface's own padding); only the vertical anchor
    // matters — drop just below the tapped icon, which already sits below the system status bar.
    override fun calculatePosition(
        anchorBounds: IntRect,
        windowSize: IntSize,
        layoutDirection: LayoutDirection,
        popupContentSize: IntSize,
    ): IntOffset = IntOffset(x = 0, y = anchorBounds.bottom + gapPx)
}
