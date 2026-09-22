package io.paritytech.polkadotapp.feature_connection_status_api.presentation

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin.ChainGlyph
import io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin.ChainHealthIndicator
import io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin.ChainHealthIndicatorsModel
import io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin.ChainHealthItemModel
import io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin.ChainLiveness
import kotlinx.collections.immutable.persistentListOf
import kotlin.math.roundToInt
import kotlin.time.Duration
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.seconds
import kotlin.time.DurationUnit
import io.paritytech.polkadotapp.common.R as RCommon

private const val PERCENT = 100

/**
 * The "Network Status" breakdown behind the tab bar's connectivity item: one row per monitored chain with
 * its indicator at panel size, its name, and what the indicator is saying. While the chain is connected and
 * producing, the row also carries the share of expected blocks it produced and the block interval that
 * share implies.
 */
@Composable
fun ChainHealthPanel(
    modifier: Modifier = Modifier,
    model: ChainHealthIndicatorsModel,
) {
    Column(modifier = modifier) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(PolkadotTheme.spacings.mediumIncreased),
            verticalArrangement = Arrangement.spacedBy(PolkadotTheme.spacings.large),
        ) {
            NovaText(
                text = stringResource(RCommon.string.chain_health_panel_title),
                style = PolkadotTheme.typography.title.large,
                color = PolkadotTheme.colors.fg.primary,
            )
            model.chains.forEach { item -> ChainRow(item = item) }
        }
    }
}

@Composable
private fun ChainRow(item: ChainHealthItemModel) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(PolkadotTheme.spacings.small),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ChainIndicator(modifier = Modifier.clearAndSetSemantics { }, item = item, indicatorSize = ChainIndicatorSize.Panel)
        Column {
            NovaText(
                text = stringResource(item.glyph.nameRes()),
                style = PolkadotTheme.typography.title.medium,
                color = PolkadotTheme.colors.fg.primary,
            )
            NovaText(
                text = summary(item),
                style = PolkadotTheme.typography.body.small,
                color = PolkadotTheme.colors.fg.secondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun summary(item: ChainHealthItemModel): String {
    val state = stringResource(item.indicator.labelRes())

    return when (val indicator = item.indicator) {
        is ChainHealthIndicator.Healthy -> connectedSummary(state, indicator.liveness)
        is ChainHealthIndicator.Production -> connectedSummary(state, indicator.liveness)
        ChainHealthIndicator.Outage,
        ChainHealthIndicator.Connecting,
        ChainHealthIndicator.Disconnected,
        ChainHealthIndicator.Offline,
        -> state
    }
}

@Composable
private fun connectedSummary(state: String, liveness: ChainLiveness?): String = stringResource(
    RCommon.string.chain_health_connected_summary,
    state,
    liveness?.let { stringResource(RCommon.string.chain_health_live_percent, (it.share * PERCENT).roundToInt()) }
        ?: stringResource(RCommon.string.chain_health_value_unknown),
    liveness?.let { stringResource(RCommon.string.chain_health_block_interval, duration(it.blockInterval)) }
        ?: stringResource(RCommon.string.chain_health_value_unknown),
)

@Composable
private fun duration(value: Duration): String {
    val seconds = value.toDouble(DurationUnit.SECONDS).roundToInt()

    return if (seconds < 1.minutes.inWholeSeconds) {
        stringResource(RCommon.string.chain_health_duration_seconds, seconds)
    } else {
        stringResource(
            RCommon.string.chain_health_duration_minutes,
            seconds / 1.minutes.inWholeSeconds,
            seconds % 1.minutes.inWholeSeconds,
        )
    }
}

// The design names rows by the chain's role, not by the registry name of whichever network is active.
private fun ChainGlyph.nameRes(): Int = when (this) {
    ChainGlyph.People -> RCommon.string.chain_health_chain_people
    ChainGlyph.AssetHub -> RCommon.string.chain_health_chain_hub
    ChainGlyph.Bulletin -> RCommon.string.chain_health_chain_bulletin
}

internal fun ChainHealthIndicator.labelRes(): Int = when (this) {
    is ChainHealthIndicator.Healthy, is ChainHealthIndicator.Production -> RCommon.string.chain_health_state_connected
    ChainHealthIndicator.Outage -> RCommon.string.chain_health_state_not_producing
    ChainHealthIndicator.Connecting -> RCommon.string.chain_health_state_connecting
    ChainHealthIndicator.Disconnected -> RCommon.string.chain_health_state_broken
    ChainHealthIndicator.Offline -> RCommon.string.chain_health_state_offline
}

@Preview(showBackground = true, backgroundColor = 0xFF000000)
@Composable
private fun ChainHealthPanelHealthyPreview() {
    PanelPreview(
        previewItem("People Chain", ChainGlyph.People, share = 13f / 15f, blockTime = 2.seconds),
        previewItem("Hub Chain", ChainGlyph.AssetHub, share = 1f, blockTime = 2.seconds),
        previewItem("Bulletin Chain", ChainGlyph.Bulletin, share = 0.9f, blockTime = 6.seconds),
    )
}

@Preview(showBackground = true, backgroundColor = 0xFF000000)
@Composable
private fun ChainHealthPanelMixedPreview() {
    PanelPreview(
        previewItem("People Chain", ChainGlyph.People, share = 0.8f, blockTime = 2.seconds),
        previewItem("Hub Chain", ChainGlyph.AssetHub, share = 0.4f, blockTime = 2.seconds),
        previewItem("Bulletin Chain", ChainGlyph.Bulletin, share = 0f, blockTime = 6.seconds),
    )
}

@Preview(showBackground = true, backgroundColor = 0xFF000000)
@Composable
private fun ChainHealthPanelDisconnectedPreview() {
    PanelPreview(
        previewItem("People Chain", ChainGlyph.People, ChainHealthIndicator.Disconnected),
        previewItem("Hub Chain", ChainGlyph.AssetHub, ChainHealthIndicator.Offline),
        previewItem("Bulletin Chain", ChainGlyph.Bulletin, ChainHealthIndicator.Connecting),
    )
}

@Composable
private fun PanelPreview(people: ChainHealthItemModel, hub: ChainHealthItemModel, bulletin: ChainHealthItemModel) {
    PolkadotTheme {
        ChainHealthPanel(
            modifier = Modifier.background(PolkadotTheme.colors.bg.surface.container),
            model = ChainHealthIndicatorsModel(persistentListOf(people, hub, bulletin)),
        )
    }
}

private fun previewItem(name: String, glyph: ChainGlyph, share: Float, blockTime: Duration) =
    previewItem(name, glyph, ChainHealthIndicator.of(share, blockTime))

private fun previewItem(name: String, glyph: ChainGlyph, indicator: ChainHealthIndicator) = ChainHealthItemModel(
    chainId = name,
    chainName = name,
    glyph = glyph,
    indicator = indicator,
)
