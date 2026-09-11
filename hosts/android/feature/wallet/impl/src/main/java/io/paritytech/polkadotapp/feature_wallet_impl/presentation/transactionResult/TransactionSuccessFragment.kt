package io.paritytech.polkadotapp.feature_wallet_impl.presentation.transactionResult

import androidx.fragment.app.viewModels
import dagger.hilt.android.AndroidEntryPoint
import io.paritytech.polkadotapp.common.R
import io.paritytech.polkadotapp.feature_transactions.api.presentation.outcome.TransactionOutcomeFragment
import io.paritytech.polkadotapp.feature_transactions.api.presentation.outcome.compose.TransactionOutcomeUiConfig

@AndroidEntryPoint
class TransactionSuccessFragment :
    TransactionOutcomeFragment<TransactionSuccessViewModel>() {
    override val viewModel: TransactionSuccessViewModel by viewModels()

    override fun config(): TransactionOutcomeUiConfig = TransactionOutcomeUiConfig.success(
        title = R.string.transaction_success_title,
        message = null,
        buttonText = R.string.common_done
    )
}
