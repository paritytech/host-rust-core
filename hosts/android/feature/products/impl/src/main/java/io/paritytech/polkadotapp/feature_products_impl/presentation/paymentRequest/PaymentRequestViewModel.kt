package io.paritytech.polkadotapp.feature_products_impl.presentation.paymentRequest

import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.withAmount
import io.paritytech.polkadotapp.common.presentation.loading.LoadingState
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.common.utils.flowOf
import io.paritytech.polkadotapp.common.utils.inBackground
import io.paritytech.polkadotapp.common.utils.launchUnit
import io.paritytech.polkadotapp.common.utils.withLoading
import io.paritytech.polkadotapp.feature_products_impl.domain.paymentRequest.PaymentRequestContext
import io.paritytech.polkadotapp.feature_products_impl.domain.paymentRequest.PaymentRequestContextHolder
import io.paritytech.polkadotapp.feature_products_impl.presentation.productBotManagement.ProductsRouter
import io.paritytech.polkadotapp.feature_tokens_api.di.DigitalDollarChainAssetProvider
import io.paritytech.polkadotapp.feature_tokens_api.domain.ChainAssetProvider
import io.paritytech.polkadotapp.feature_tokens_api.presentation.mapper.TokenAmountMapper
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import javax.inject.Inject

@HiltViewModel
class PaymentRequestViewModel @Inject constructor(
    private val router: ProductsRouter,
    private val context: PaymentRequestContext,
    private val holder: PaymentRequestContextHolder,
    @param:DigitalDollarChainAssetProvider private val chainAssetProvider: ChainAssetProvider,
    private val tokenAmountMapper: TokenAmountMapper,
) : BaseViewModel(), PaymentRequestContract {
    override val state: StateFlow<LoadingState<PaymentRequestUiState>> = flowOf {
        val asset = chainAssetProvider.asset()

        Result.success(
            PaymentRequestUiState(
                productId = context.productId.value,
                amount = tokenAmountMapper.mapFrom(asset.withAmount(context.amount)),
            )
        )
    }
        .withLoading("PaymentRequest")
        .inBackground()
        .stateIn(this, SharingStarted.Eagerly, LoadingState.Loading)

    override fun onApproveClicked() = launchUnit {
        context.deliverApproved()
        router.back()
    }

    override fun onRejectClicked() = launchUnit {
        context.deliverRejected()
        router.back()
    }

    override fun onCleared() {
        super.onCleared()
        holder.clear()
    }
}
