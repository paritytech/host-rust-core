package io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.models

import io.paritytech.polkadotapp.feature_tokens_api.presentation.model.TokenAmountModel

data class WeeklyGameDepositState(
    val isVisible: Boolean = false,
    val requiredAmount: TokenAmountModel? = null,
    val inProgress: Boolean = false
)
