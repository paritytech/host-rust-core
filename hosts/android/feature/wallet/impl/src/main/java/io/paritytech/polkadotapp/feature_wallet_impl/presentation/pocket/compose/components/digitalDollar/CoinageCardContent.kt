@file:OptIn(ExperimentalMaterial3Api::class)

package io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.digitalDollar

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import io.paritytech.polkadotapp.design.components.bottomsheet.NovaModalBottomSheet
import io.paritytech.polkadotapp.design.components.button.common.PolkadotButtonStyle
import io.paritytech.polkadotapp.design.components.button.default.PolkadotTextButton
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.Coin
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.models.CoinageUiState
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun CoinageCardContent(
    state: CoinageUiState,
    onAutoFundClick: () -> Unit,
    onShareLogsClick: () -> Unit,
    onForceRecycleClick: (Coin) -> Unit
) {
    Column {
        var details by remember { mutableStateOf<CoinageDetails?>(null) }

        if (state.autoFundAvailable) {
            FaucetTopUpButton(
                modifier = Modifier.fillMaxWidth(),
                fundInProgress = state.fundInProgress,
                actionsEnabled = state.actionsEnabled,
                onClick = onAutoFundClick
            )
        }

        if (state.coinageWidgetsEnabled) {
            VerticalSpacer { mediumIncreased }

            CoinageStateCard(
                state = state.tokensState,
                onCoinsClick = { details = CoinageDetails.COINS },
                onVouchersClick = { details = CoinageDetails.VOUCHERS },
                onShareLogsClick = onShareLogsClick
            )

            NovaModalBottomSheet(
                isVisible = details == CoinageDetails.COINS,
                onDismissRequest = { details = null }
            ) {
                CoinsListSheetContent(
                    coins = state.tokensState.coinList,
                    onForceRecycleClick = onForceRecycleClick
                )
            }

            NovaModalBottomSheet(
                isVisible = details == CoinageDetails.VOUCHERS,
                onDismissRequest = { details = null }
            ) {
                VouchersListSheetContent(vouchers = state.tokensState.voucherList)
            }
        }
    }
}

@Composable
private fun FaucetTopUpButton(
    modifier: Modifier = Modifier,
    fundInProgress: Boolean,
    actionsEnabled: Boolean,
    onClick: () -> Unit
) {
    PolkadotTextButton(
        modifier = modifier,
        text = stringResource(RCommon.string.pocket_digital_dollar_faucet_top_up),
        style = PolkadotButtonStyle.secondary(),
        enabled = actionsEnabled,
        loading = fundInProgress,
        onClick = onClick
    )
}
