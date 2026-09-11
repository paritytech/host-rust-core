package io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.digitalDollar

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.design.components.button.default.PolkadotTextButton
import io.paritytech.polkadotapp.design.components.icon.NovaIcon
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.ArrowRight
import io.paritytech.polkadotapp.design.components.spacer.FillerSpacer
import io.paritytech.polkadotapp.design.components.spacer.HorizontalSpacer
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_tokens_api.presentation.formatter.LocalTokenAmountFormatter
import io.paritytech.polkadotapp.feature_tokens_api.presentation.formatter.TokenAmountFormatter
import io.paritytech.polkadotapp.feature_tokens_api.presentation.formatter.formatFiat
import io.paritytech.polkadotapp.feature_tokens_api.presentation.model.TokenAmountModel
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.models.CoinageUiState
import kotlinx.collections.immutable.persistentListOf

@Composable
internal fun CoinageStateCard(
    modifier: Modifier = Modifier,
    state: CoinageUiState.TokensState,
    onCoinsClick: () -> Unit,
    onVouchersClick: () -> Unit,
    onShareLogsClick: () -> Unit
) {
    val formatter = LocalTokenAmountFormatter.current

    PolkadotSurface(
        modifier = modifier
            .fillMaxWidth(),
        shape = RoundedCornerShape(
            topStart = 24.dp,
            topEnd = 24.dp,
            bottomStart = 20.dp,
            bottomEnd = 20.dp
        ),
        color = Color(0x1FFFFFFF)
    ) {
        Column {
            NovaText(
                modifier = Modifier.padding(16.dp),
                style = PolkadotTheme.typography.title.medium,
                text = "Coinage Balance",
                color = PolkadotTheme.colors.fg.primary
            )

            Row(modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) {
                NovaText(
                    text = "Total Balance",
                    color = PolkadotTheme.colors.fg.primary
                )
                FillerSpacer()
                NovaText(
                    text = formatter.formatFiat(state.totalBalance),
                    color = PolkadotTheme.colors.fg.primary
                )
            }

            Row(modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) {
                NovaText(
                    text = "Spendable Balance",
                    color = PolkadotTheme.colors.fg.primary
                )
                FillerSpacer()
                NovaText(
                    text = formatter.formatFiat(state.spendableBalance),
                    color = PolkadotTheme.colors.fg.primary
                )
            }

            Row(modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) {
                NovaText(
                    text = "Gaining Privacy",
                    color = PolkadotTheme.colors.fg.primary
                )
                FillerSpacer()
                NovaText(
                    text = formatter.formatFiat(state.gainingPrivacyBalance),
                    color = PolkadotTheme.colors.fg.primary
                )
            }

            Row(modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) {
                NovaText(
                    text = "Pending",
                    color = PolkadotTheme.colors.fg.primary
                )
                FillerSpacer()
                NovaText(
                    text = formatter.formatFiat(state.pendingBalance),
                    color = PolkadotTheme.colors.fg.primary
                )
            }

            VerticalSpacer { 8.dp }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onCoinsClick() }
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                NovaText(
                    text = "Coins",
                    color = PolkadotTheme.colors.fg.primary
                )
                FillerSpacer()
                NovaText(
                    text = state.coinList.size.toString(),
                    color = PolkadotTheme.colors.fg.primary
                )
                HorizontalSpacer { 4.dp }
                NovaIcon(
                    modifier = Modifier.size(16.dp),
                    imageVector = NovaIcons.ArrowRight,
                    tint = PolkadotTheme.colors.fg.tertiary
                )
            }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onVouchersClick() }
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                NovaText(text = "Vouchers", color = PolkadotTheme.colors.fg.primary)
                FillerSpacer()
                NovaText(text = state.voucherList.size.toString(), color = PolkadotTheme.colors.fg.primary)
                HorizontalSpacer { 4.dp }
                NovaIcon(
                    modifier = Modifier.size(16.dp),
                    imageVector = NovaIcons.ArrowRight,
                    tint = PolkadotTheme.colors.fg.tertiary
                )
            }

            PolkadotTextButton(
                text = "Share Coinage Logs",
                onClick = { onShareLogsClick() },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp)
                    .padding(bottom = 16.dp)
            )
        }
    }
}

@Preview
@Composable
private fun CoinageStateCardPreview() {
    CompositionLocalProvider(
        LocalTokenAmountFormatter provides TokenAmountFormatter.mocked
    ) {
        PolkadotTheme {
            CoinageStateCard(
                state = CoinageUiState.TokensState(
                    totalBalance = TokenAmountModel.mock,
                    spendableBalance = TokenAmountModel.mock,
                    gainingPrivacyBalance = TokenAmountModel.mock,
                    pendingBalance = TokenAmountModel.mock,
                    coinList = persistentListOf(),
                    voucherList = persistentListOf()
                ),
                onCoinsClick = {},
                onVouchersClick = {},
                onShareLogsClick = {}
            )
        }
    }
}
