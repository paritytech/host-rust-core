package io.paritytech.polkadotapp.feature_products_impl.presentation.truapiContactPick

import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.presentation.loading.LoadingState
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.common.utils.inBackground
import io.paritytech.polkadotapp.common.utils.launchUnit
import io.paritytech.polkadotapp.common.utils.withLoading
import io.paritytech.polkadotapp.feature_products_impl.domain.truapi.TrUAPIContactPickContext
import io.paritytech.polkadotapp.feature_products_impl.domain.truapi.TrUAPIContactPickContextHolder
import io.paritytech.polkadotapp.feature_products_impl.presentation.productBotManagement.ProductsRouter
import kotlinx.collections.immutable.toImmutableList
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import javax.inject.Inject

@HiltViewModel
class TrUAPIContactPickViewModel @Inject constructor(
    private val router: ProductsRouter,
    private val context: TrUAPIContactPickContext,
    private val holder: TrUAPIContactPickContextHolder,
) : BaseViewModel(), TrUAPIContactPickContract {
    private val choosing = MutableStateFlow(false)

    init {
        context.markShown()
    }

    override val state: StateFlow<LoadingState<TrUAPIContactPickUiState>> =
        choosing.map { toUiState() }
            .withLoading("TrUAPIContactPick")
            .inBackground()
            .stateIn(this, SharingStarted.Eagerly, LoadingState.Loading)

    override fun onContactClicked(index: Int) = answer {
        context.options.getOrNull(index)?.let(context::pick) ?: context.dismiss()
    }

    override fun onDismissClicked() = answer { context.dismiss() }

    override fun onCleared() {
        // The core is still blocked if the sheet went away unanswered, so a
        // dismissal has to resolve as naming nobody.
        context.dismiss()
        holder.clear(context)
        super.onCleared()
    }

    private fun toUiState() = TrUAPIContactPickUiState(
        productId = context.productId,
        contacts = context.options.mapIndexed { index, option ->
            TrUAPIContactPickRow(index = index, name = option.displayName)
        }.toImmutableList(),
    )

    private fun answer(choose: () -> Unit) = launchUnit {
        if (choosing.value) return@launchUnit
        choosing.value = true
        choose()
        router.back()
    }
}
