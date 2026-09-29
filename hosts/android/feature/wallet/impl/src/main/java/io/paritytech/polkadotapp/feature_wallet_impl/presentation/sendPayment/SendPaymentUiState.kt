package io.paritytech.polkadotapp.feature_wallet_impl.presentation.sendPayment

import androidx.annotation.StringRes
import androidx.compose.runtime.Immutable
import io.paritytech.polkadotapp.common.presentation.search.SearchState
import io.paritytech.polkadotapp.common.utils.SizedList
import io.paritytech.polkadotapp.design.components.avatar.AvatarUiModel
import io.paritytech.polkadotapp.feature_account_api.presentation.address.model.ExtractedAddress
import kotlinx.collections.immutable.ImmutableList

@Immutable
data class PaymentSearchSectionUiModel(
    val key: String,
    @StringRes val titleRes: Int,
    val items: ImmutableList<PaymentSearchResultUiModel>,
)

data class PaymentSearchResultUiModel(
    val extractedAddress: ExtractedAddress,
    val avatarModel: AvatarUiModel,
)

data class SendPaymentUiState(
    val input: String = "",
    val searchState: SearchState<SizedList<PaymentSearchSectionUiModel>> = SearchState.Loading,
)
