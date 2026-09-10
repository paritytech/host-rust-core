package io.paritytech.polkadotapp.feature_connection_status_api.presentation

import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material3.LocalMinimumInteractiveComponentSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.design.components.icon.NovaIcon
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.AssetHub
import io.paritytech.polkadotapp.design.components.icon.vectors.Bulletin
import io.paritytech.polkadotapp.design.components.icon.vectors.People
import io.paritytech.polkadotapp.design.components.progress.NovaCircularProgressIndicator
import io.paritytech.polkadotapp.design.components.spacer.HorizontalSpacer
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainConnectionPresentation
import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainHealthScore
import io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin.ChainGlyph
import io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin.ChainHealthBarModel
import io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin.ChainHealthItemModel

private val ICON_SIZE = 20.dp
private val GLYPH_SIZE = 11.dp
private val RING_STROKE = 1.5f.dp

// Health-score colour tiers: white (best) -> green -> amber -> red -> gray (stalled).
private const val TIER_HIGH = 90
private const val TIER_GOOD = 70
private const val TIER_FAIR = 40

object ChainHealthBarDefaults {
    /**
     * Height of the bar's content row, excluding the status-bar inset. The root also inflates the
     * content's top window inset by this amount so screens sit below the bar while their backgrounds
     * still draw full-bleed behind it.
     */
    val ContentHeight = ICON_SIZE
}

/**
 * The always-on chain-health bar, overlaid at the very top like the system status indicators: one
 * icon per monitored chain, the inner glyph reflecting connection and the ring the health score.
 * Transparent, so whatever the screen draws behind it (including custom backgrounds) stays visible.
 */
@Composable
fun ChainHealthBar(
    modifier: Modifier = Modifier,
    model: ChainHealthBarModel,
) {
    // Clickable icons otherwise inflate the row to the 48dp minimum touch target; the bar is
    // deliberately tighter than that.
    CompositionLocalProvider(LocalMinimumInteractiveComponentSize provides Dp.Unspecified) {
        Row(
            modifier = modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .height(ChainHealthBarDefaults.ContentHeight)
                .padding(horizontal = PolkadotTheme.spacings.medium),
            horizontalArrangement = Arrangement.End,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            model.chains.forEachIndexed { index, item ->
                if (index > 0) HorizontalSpacer { small }
                ChainHealthIcon(item = item)
            }
        }
    }
}

@Composable
private fun ChainHealthIcon(item: ChainHealthItemModel) {
    var showDetails by remember { mutableStateOf(false) }

    Box(
        modifier = Modifier
            .size(ICON_SIZE)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { showDetails = true },
        contentAlignment = Alignment.Center,
    ) {
        if (item.connection == ChainConnectionPresentation.Connecting) {
            NovaCircularProgressIndicator(
                modifier = Modifier.fillMaxSize(),
                color = PolkadotTheme.colors.fg.disabled,
                strokeWidth = RING_STROKE,
            )
        } else {
            NovaCircularProgressIndicator(
                modifier = Modifier.fillMaxSize(),
                progress = { item.score.fraction },
                color = ringColor(item.score),
                trackColor = PolkadotTheme.colors.fg.tertiary,
                strokeWidth = RING_STROKE,
            )
        }

        NovaIcon(
            // extraTiny inset so the glyph doesn't crowd the ring.
            modifier = Modifier
                .size(GLYPH_SIZE)
                .padding(1.dp),
            imageVector = item.glyph.imageVector(),
            tint = glyphTint(item.connection),
            contentDescription = item.chainName,
        )

        ChainHealthDetailsPopover(
            expanded = showDetails,
            item = item,
            onDismiss = { showDetails = false },
        )
    }
}

@Composable
private fun ringColor(score: ChainHealthScore): Color = when {
    score.value >= TIER_HIGH -> PolkadotTheme.colors.fg.primary
    score.value >= TIER_GOOD -> PolkadotTheme.colors.fg.success
    score.value >= TIER_FAIR -> PolkadotTheme.colors.fg.warning
    score.value > ChainHealthScore.MIN_VALUE -> PolkadotTheme.colors.fg.error
    else -> PolkadotTheme.colors.fg.disabled
}

@Composable
private fun glyphTint(connection: ChainConnectionPresentation): Color = when (connection) {
    ChainConnectionPresentation.Connected -> PolkadotTheme.colors.fg.primary
    ChainConnectionPresentation.Connecting,
    ChainConnectionPresentation.Disconnected,
    -> PolkadotTheme.colors.fg.disabled
}

private fun ChainGlyph.imageVector(): ImageVector = when (this) {
    ChainGlyph.People -> NovaIcons.People
    ChainGlyph.AssetHub -> NovaIcons.AssetHub
    ChainGlyph.Bulletin -> NovaIcons.Bulletin
}
