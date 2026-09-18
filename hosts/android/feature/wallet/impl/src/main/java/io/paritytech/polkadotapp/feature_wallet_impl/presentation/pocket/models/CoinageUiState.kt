package io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.models

import androidx.compose.runtime.Immutable
import io.paritytech.polkadotapp.feature_tokens_api.presentation.model.TokenAmountModel
import kotlinx.collections.immutable.ImmutableList

@Immutable
data class CoinageUiState(
    val tokensState: TokensState,
    val autoFundAvailable: Boolean,
    val fundInProgress: Boolean,
    val actionsEnabled: Boolean,
    val coinageWidgetsEnabled: Boolean,
    /**
     * Gates log sharing alone, separately from [coinageWidgetsEnabled].
     *
     * The two flags happen to carry the same value in every build type, so this changes no exposure today —
     * it keeps the reason legible: sharing a log file is testnet support tooling, not a coinage widget.
     */
    val shareLogsEnabled: Boolean,
    val detailsVisible: Boolean,
    val keyVisible: Boolean
) {
    /**
     * The last two figures partition [totalBalance] exactly, and [composition] is a picture of the same
     * two — so the numbers and the bar are read off one classification and cannot contradict each other.
     */
    @Immutable
    data class TokensState(
        val totalBalance: TokenAmountModel,
        /** Free to use without giving up any privacy. */
        val readyBalance: TokenAmountModel,
        /** Everything else: gaining privacy, in flight, or due to be recycled before it can be used. */
        val clearingBalance: TokenAmountModel,
        val composition: CoinageCompositionUiModel,
        val holdings: ImmutableList<CoinageHoldingUiModel>,
        val breakdown: CoinageBalanceBreakdownUiModel
    )
}
