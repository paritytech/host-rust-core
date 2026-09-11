package io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.models

import io.paritytech.polkadotapp.common.presentation.loading.LoadingState
import io.paritytech.polkadotapp.feature_tokens_api.presentation.model.TokenAmountModel
import io.paritytech.polkadotapp.feature_wallet_impl.domain.model.PocketRank

sealed interface PocketCardUiModel {
    val id: String

    data class DigitalDollar(
        val amounts: LoadingState<Amounts>,
        val syncInProgress: Boolean
    ) : PocketCardUiModel {
        override val id = "digital_dollar_card"

        data class Amounts(
            val balance: TokenAmountModel,
            val available: TokenAmountModel
        ) {
            val notFullyAvailable: Boolean
                get() = balance.amount != available.amount
        }
    }

    data class IdCard(
        val username: String,
        val address: String,
        val rank: PocketRank
    ) : PocketCardUiModel {
        override val id = "id_card"
    }
}
