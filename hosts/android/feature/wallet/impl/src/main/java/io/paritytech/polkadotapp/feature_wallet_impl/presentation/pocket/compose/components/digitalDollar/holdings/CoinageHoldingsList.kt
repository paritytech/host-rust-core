package io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.digitalDollar.holdings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_tokens_api.presentation.formatter.LocalTokenAmountFormatter
import io.paritytech.polkadotapp.feature_tokens_api.presentation.model.RoundPrecision
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.models.CoinageHoldingUiModel
import kotlinx.collections.immutable.ImmutableList

/**
 * Coins and vouchers in one two-column grid.
 *
 * Built as two `Column`s side by side rather than a stack of `Row`s, which is what gives the amount column
 * one width for every row: a `Column` is as wide as its widest child, so every depiction starts at the same
 * x and bar lengths stay comparable down the list. Sizing each row on its own would give the bars different
 * columns to scale against and make the lengths meaningless between rows.
 *
 * Not a `LazyColumn`: the whole card already sits inside a vertical scroll, and nesting two scrollers on the
 * same axis is illegal in Compose.
 */
@Composable
internal fun CoinageHoldingsList(
    modifier: Modifier = Modifier,
    holdings: ImmutableList<CoinageHoldingUiModel>,
) {
    val formatter = LocalTokenAmountFormatter.current
    val stripePhase = rememberBarberPolePhase()
    val colors = rememberHoldingColors()

    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(HoldingGeometry.detailsColumnSpacing)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(HoldingGeometry.detailsRowSpacing)) {
            holdings.forEach { holding ->
                HoldingAmount(
                    text = formatter.formatTokenAmount(
                        tokenAmount = holding.value,
                        precision = RoundPrecision.FIAT,
                        withSymbol = false
                    )
                )
            }
        }

        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(HoldingGeometry.detailsRowSpacing)
        ) {
            holdings.forEach { holding ->
                when (holding) {
                    is CoinageHoldingUiModel.CoinRow -> CoinStatusGraphics(row = holding, colors = colors)

                    is CoinageHoldingUiModel.VoucherRow -> VoucherStatusGraphics(
                        row = holding,
                        stripePhase = stripePhase,
                        colors = colors
                    )
                }
            }
        }
    }
}

/** Bare number, no symbol: the symbol appears once, beside the total in the headline. */
@Composable
private fun HoldingAmount(text: String) {
    Box(
        modifier = Modifier.height(HoldingGeometry.markHeight),
        contentAlignment = Alignment.CenterEnd
    ) {
        NovaText(
            text = text,
            maxLines = 1,
            textAlign = TextAlign.End,
            style = PolkadotTheme.typography.body.medium,
            color = PolkadotTheme.colors.fg.primary
        )
    }
}
