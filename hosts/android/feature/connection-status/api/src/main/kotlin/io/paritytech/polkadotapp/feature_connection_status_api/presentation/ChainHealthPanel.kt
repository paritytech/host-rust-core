package io.paritytech.polkadotapp.feature_connection_status_api.presentation

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
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
import io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin.ChainHealthIndicator.Speed
import io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin.ChainHealthIndicatorsModel
import io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin.ChainHealthItemModel
import kotlinx.collections.immutable.persistentListOf
import kotlinx.coroutines.delay
import kotlin.time.Clock
import kotlin.time.Duration
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.seconds
import kotlin.time.Instant
import io.paritytech.polkadotapp.common.R as RCommon

private val BLOCK_AGE_TICK = 1.seconds

/**
 * The "Network Status" breakdown behind the tab bar's connectivity item: one row per monitored chain with
 * its indicator at panel size, its name, what the indicator is saying alongside the chain's block time,
 * and how long ago its last block landed.
 */
@Composable
fun ChainHealthPanel(
    modifier: Modifier = Modifier,
    model: ChainHealthIndicatorsModel,
) {
    // The rows only re-emit when the health changes, so a stalled chain would stop emitting entirely.
    // Ageing the last block on this tick instead keeps the counter running through exactly that stall.
    val now by produceState(Clock.System.now()) {
        while (true) {
            delay(BLOCK_AGE_TICK)
            value = Clock.System.now()
        }
    }

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
            model.chains.forEach { item -> ChainRow(item = item, now = now) }
        }
    }
}

@Composable
private fun ChainRow(item: ChainHealthItemModel, now: Instant) {
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
                text = stringResource(
                    RCommon.string.chain_health_summary,
                    stringResource(item.indicator.labelRes()),
                    blockAge(item.lastBlockAt, now),
                ),
                style = PolkadotTheme.typography.body.small,
                color = PolkadotTheme.colors.fg.secondary,
                // A long stall pushes the age into minutes; wrapping it would grow the row on a tick.
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun blockAge(lastBlockAt: Instant?, now: Instant): String {
    val age = lastBlockAt?.let { (now - it).coerceAtLeast(Duration.ZERO) }

    return when {
        age == null -> stringResource(RCommon.string.chain_health_block_age_unknown)
        age < 1.minutes -> stringResource(RCommon.string.chain_health_block_age_seconds, age.inWholeSeconds)
        else -> stringResource(
            RCommon.string.chain_health_block_age_minutes,
            age.inWholeMinutes,
            age.inWholeSeconds % 1.minutes.inWholeSeconds,
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
    ChainHealthIndicator.Healthy -> RCommon.string.chain_health_state_speed_high
    ChainHealthIndicator.Outage -> RCommon.string.chain_health_state_not_producing
    is ChainHealthIndicator.ConnectionSpeed -> when (speed) {
        Speed.Good -> RCommon.string.chain_health_state_speed_good
        Speed.Fair -> RCommon.string.chain_health_state_speed_fair
        Speed.Low -> RCommon.string.chain_health_state_speed_low
    }
    ChainHealthIndicator.Connecting -> RCommon.string.chain_health_state_connecting
    ChainHealthIndicator.Disconnected -> RCommon.string.chain_health_state_broken
}

@Preview(showBackground = true, backgroundColor = 0xFF000000)
@Composable
private fun ChainHealthPanelHealthyPreview() {
    PanelPreview(
        ChainHealthIndicator.ConnectionSpeed(Speed.Good, arc = 0.72f),
        ChainHealthIndicator.ConnectionSpeed(Speed.Good, arc = 0.56f),
        ChainHealthIndicator.ConnectionSpeed(Speed.Good, arc = 0.68f),
    )
}

@Preview(showBackground = true, backgroundColor = 0xFF000000)
@Composable
private fun ChainHealthPanelMixedPreview() {
    PanelPreview(
        ChainHealthIndicator.Healthy,
        ChainHealthIndicator.ConnectionSpeed(Speed.Fair, arc = 0.38f),
        ChainHealthIndicator.Outage,
    )
}

@Preview(showBackground = true, backgroundColor = 0xFF000000)
@Composable
private fun ChainHealthPanelDisconnectedPreview() {
    PanelPreview(
        ChainHealthIndicator.Disconnected,
        ChainHealthIndicator.Disconnected,
        ChainHealthIndicator.Connecting,
    )
}

@Composable
private fun PanelPreview(people: ChainHealthIndicator, hub: ChainHealthIndicator, bulletin: ChainHealthIndicator) {
    PolkadotTheme {
        ChainHealthPanel(
            modifier = Modifier.background(PolkadotTheme.colors.bg.surface.container),
            model = ChainHealthIndicatorsModel(
                persistentListOf(
                    previewItem("People Chain", ChainGlyph.People, people, 6.seconds),
                    previewItem("Hub Chain", ChainGlyph.AssetHub, hub, 12.seconds),
                    previewItem("Bulletin Chain", ChainGlyph.Bulletin, bulletin, 6.seconds),
                ),
            ),
        )
    }
}

private fun previewItem(name: String, glyph: ChainGlyph, indicator: ChainHealthIndicator, blockAge: Duration) =
    ChainHealthItemModel(
        chainName = name,
        glyph = glyph,
        indicator = indicator,
        lastBlockAt = Clock.System.now() - blockAge,
    )
