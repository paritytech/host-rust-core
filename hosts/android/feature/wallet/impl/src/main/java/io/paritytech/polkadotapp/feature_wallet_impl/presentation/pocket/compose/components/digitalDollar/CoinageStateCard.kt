package io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.digitalDollar

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import io.paritytech.polkadotapp.common.presentation.compose.withCurrencyTickerStyle
import io.paritytech.polkadotapp.common.presentation.paymentAsset.LocalPaymentAssetBrand
import io.paritytech.polkadotapp.common.presentation.paymentAsset.PaymentAssetBrand
import io.paritytech.polkadotapp.design.components.icon.NovaIcon
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.ArrowDownward
import io.paritytech.polkadotapp.design.components.icon.vectors.ArrowUpwards
import io.paritytech.polkadotapp.design.components.spacer.HorizontalSpacer
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_tokens_api.presentation.formatter.LocalTokenAmountFormatter
import io.paritytech.polkadotapp.feature_tokens_api.presentation.formatter.TokenAmountFormatter
import io.paritytech.polkadotapp.feature_tokens_api.presentation.formatter.formatFiatSigned
import io.paritytech.polkadotapp.feature_tokens_api.presentation.model.TokenAmountModel
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.digitalDollar.holdings.CoinageCompositionBar
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.digitalDollar.holdings.CoinageHoldingsList
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.digitalDollar.holdings.CoinageLegendSwatch
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.digitalDollar.holdings.HoldingColors
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.digitalDollar.holdings.HoldingGeometry
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.digitalDollar.holdings.rememberBarberPolePhase
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.digitalDollar.holdings.rememberHoldingColors
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.models.CoinageBalanceBreakdownUiModel
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.models.CoinageCompositionUiModel
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.models.CoinageUiState
import kotlinx.collections.immutable.persistentListOf
import io.paritytech.polkadotapp.common.R as RCommon

/**
 * The total, the partition of it, and the holdings it is made of.
 *
 * The two category figures partition the total exactly, and the bar above them is a picture of the same
 * two buckets in the same order — both are read off one classification, so they cannot contradict each
 * other. Summing the details rows by availability reproduces the figures for the same reason.
 *
 * "Ready" and "Clearing" are deliberately not the pallet's words: "recycler" and its relatives stay in code
 * identifiers and never reach the screen. Clearing folds together everything that is not ready yet, whatever
 * the reason, because to the user those reasons look alike.
 */
@Composable
internal fun CoinageStateCard(
    modifier: Modifier = Modifier,
    state: CoinageUiState.TokensState,
    detailsVisible: Boolean,
    keyVisible: Boolean,
    onDetailsToggled: () -> Unit,
    onKeyToggled: () -> Unit
) {
    val colors = rememberHoldingColors()
    val stripePhase = rememberBarberPolePhase()

    CoinageWidgetCard(
        modifier = modifier,
        title = stringResource(RCommon.string.pocket_coinage_balance_title)
    ) {
        Headline(total = state.totalBalance)

        CoinageCompositionBar(
            modifier = Modifier
                .fillMaxWidth()
                .height(HoldingGeometry.summaryBarHeight),
            composition = state.composition,
            colors = colors
        )

        CategoryLegend(state = state, colors = colors)

        if (state.totalBalance.amount.signum() > 0) {
            DetailsToggle(expanded = detailsVisible, onClick = onDetailsToggled)

            // The key belongs to the details, not to the summary: it explains marks that are only on screen
            // while the list is open, so it goes away with them.
            AnimatedVisibility(visible = detailsVisible) {
                Column(verticalArrangement = Arrangement.spacedBy(HoldingGeometry.containerSpacing)) {
                    CoinageHoldingsList(
                        modifier = Modifier.fillMaxWidth(),
                        holdings = state.holdings
                    )

                    CoinageKey(
                        expanded = keyVisible,
                        onToggle = onKeyToggled,
                        colors = colors,
                        stripePhase = stripePhase
                    )
                }
            }
        }
    }
}

@Composable
private fun Headline(total: TokenAmountModel) {
    val formatter = LocalTokenAmountFormatter.current

    Row(horizontalArrangement = Arrangement.spacedBy(HoldingGeometry.headlineSpacing)) {
        NovaText(
            modifier = Modifier.alignByBaseline(),
            text = formatter.formatFiatSigned(total),
            maxLines = 1,
            style = PolkadotTheme.typography.headline.large,
            color = PolkadotTheme.colors.fg.primary
        )
        NovaText(
            modifier = Modifier.alignByBaseline(),
            text = LocalPaymentAssetBrand.current.symbol.withCurrencyTickerStyle(PolkadotTheme.typography.headline.large),
            style = PolkadotTheme.typography.headline.large,
            color = PolkadotTheme.colors.fg.secondary
        )
    }
}

/**
 * Two rows rather than stacked columns, so a label that wraps cannot push its own value onto a different
 * line. Every cell takes an equal share, leading-aligned.
 */
@Composable
private fun CategoryLegend(
    state: CoinageUiState.TokensState,
    colors: HoldingColors
) {
    val formatter = LocalTokenAmountFormatter.current

    Column(verticalArrangement = Arrangement.spacedBy(HoldingGeometry.legendRowSpacing)) {
        Row(horizontalArrangement = Arrangement.spacedBy(HoldingGeometry.legendColumnSpacing)) {
            LegendLabel(
                modifier = Modifier.weight(1f),
                label = stringResource(RCommon.string.pocket_coinage_ready),
                fill = colors.spendable,
                clearing = false,
                colors = colors
            )
            LegendLabel(
                modifier = Modifier.weight(1f),
                label = stringResource(RCommon.string.pocket_coinage_clearing),
                fill = null,
                clearing = true,
                colors = colors
            )
        }

        Row(horizontalArrangement = Arrangement.spacedBy(HoldingGeometry.legendColumnSpacing)) {
            listOf(state.readyBalance, state.clearingBalance).forEach { amount ->
                NovaText(
                    modifier = Modifier.weight(1f),
                    text = formatter.formatFiatSigned(amount),
                    maxLines = 1,
                    style = PolkadotTheme.typography.title.small,
                    color = PolkadotTheme.colors.fg.primary
                )
            }
        }
    }
}

@Composable
private fun LegendLabel(
    modifier: Modifier = Modifier,
    label: String,
    fill: Color?,
    clearing: Boolean,
    colors: HoldingColors
) {
    Row(modifier = modifier, verticalAlignment = Alignment.CenterVertically) {
        CoinageLegendSwatch(fill = fill, clearing = clearing, colors = colors)

        HorizontalSpacer { HoldingGeometry.legendSwatchLabelSpacing }

        NovaText(
            text = label,
            maxLines = 1,
            style = PolkadotTheme.typography.body.small,
            color = PolkadotTheme.colors.fg.secondary
        )
    }
}

@Composable
private fun DetailsToggle(expanded: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(vertical = PolkadotTheme.spacings.small),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center
    ) {
        NovaIcon(
            modifier = Modifier.size(HoldingGeometry.legendSwatch),
            imageVector = if (expanded) NovaIcons.ArrowUpwards else NovaIcons.ArrowDownward,
            tint = PolkadotTheme.colors.fg.secondary
        )

        HorizontalSpacer { HoldingGeometry.legendSwatchLabelSpacing }

        NovaText(
            text = stringResource(RCommon.string.pocket_coinage_show_details),
            style = PolkadotTheme.typography.title.small,
            color = PolkadotTheme.colors.fg.primary
        )
    }
}

@Preview
@Composable
private fun CoinageStateCardPreview() {
    CompositionLocalProvider(
        LocalTokenAmountFormatter provides TokenAmountFormatter.mocked,
        LocalPaymentAssetBrand provides PaymentAssetBrand.mocked
    ) {
        PolkadotTheme {
            CoinageStateCard(
                modifier = Modifier.fillMaxWidth(),
                state = CoinageUiState.TokensState(
                    totalBalance = TokenAmountModel.mock,
                    readyBalance = TokenAmountModel.mock,
                    clearingBalance = TokenAmountModel.mock,
                    composition = CoinageCompositionUiModel(readyFraction = 0.6f, clearingFraction = 0.4f),
                    holdings = persistentListOf(),
                    breakdown = CoinageBalanceBreakdownUiModel(
                        availablePrivate = TokenAmountModel.mock,
                        gainingPrivacy = TokenAmountModel.mock,
                        pending = TokenAmountModel.mock,
                        canSpendGainingPrivacy = true
                    )
                ),
                detailsVisible = false,
                keyVisible = false,
                onDetailsToggled = {},
                onKeyToggled = {}
            )
        }
    }
}
