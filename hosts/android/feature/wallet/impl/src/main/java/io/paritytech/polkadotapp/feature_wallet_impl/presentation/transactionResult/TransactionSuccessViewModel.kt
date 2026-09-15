package io.paritytech.polkadotapp.feature_wallet_impl.presentation.transactionResult

import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.feature_transactions.api.presentation.outcome.TransactionOutcomeViewModel
import io.paritytech.polkadotapp.feature_wallet_impl.PocketRouter
import javax.inject.Inject

@HiltViewModel
class TransactionSuccessViewModel @Inject constructor(
    private val walletRouter: PocketRouter,
) : TransactionOutcomeViewModel() {
    override fun onButtonClick() {
        walletRouter.back()
    }

    override fun onBackClick() {
        walletRouter.back()
    }
}
