package io.paritytech.polkadotapp.feature_tokens_api.presentation.model

import io.paritytech.polkadotapp.common.utils.CurrencyConfig

sealed interface TokenSymbolAppearance {
    val symbol: String

    object DigitalDollar : TokenSymbolAppearance {
        override val symbol: String = CurrencyConfig.symbol
    }

    class Symbol(override val symbol: String) : TokenSymbolAppearance
}
