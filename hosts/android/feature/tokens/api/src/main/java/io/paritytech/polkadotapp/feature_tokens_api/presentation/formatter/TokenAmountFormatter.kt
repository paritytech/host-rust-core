package io.paritytech.polkadotapp.feature_tokens_api.presentation.formatter

import androidx.compose.runtime.staticCompositionLocalOf
import io.paritytech.polkadotapp.common.utils.Fraction
import io.paritytech.polkadotapp.design.utils.noLocalProvidedFor
import io.paritytech.polkadotapp.feature_tokens_api.presentation.model.RoundPrecision
import io.paritytech.polkadotapp.feature_tokens_api.presentation.model.TokenAmountModel
import java.math.BigDecimal

val LocalTokenAmountFormatter = staticCompositionLocalOf<TokenAmountFormatter> {
    noLocalProvidedFor("TokenAmountFormatter")
}

interface TokenAmountFormatter {
    fun formatTokenAmount(
        tokenAmount: TokenAmountModel,
        precision: RoundPrecision,
        approx: Boolean = false,
        withSymbol: Boolean = true
    ): String

    fun formatAmount(
        amount: BigDecimal,
        precision: RoundPrecision = RoundPrecision.DEFAULT,
    ): String

    fun formatToSymbol(tokenAmount: TokenAmountModel): String

    fun formatPercent(value: Fraction): String

    fun formatIntegralPercent(value: Fraction): String

    companion object {
        val mocked: TokenAmountFormatter get() = MockedAmountFormatter()
    }
}

fun TokenAmountFormatter.formatFiat(model: TokenAmountModel): String =
    formatTokenAmount(model, RoundPrecision.FIAT)

private class MockedAmountFormatter : TokenAmountFormatter {
    override fun formatTokenAmount(
        tokenAmount: TokenAmountModel,
        precision: RoundPrecision,
        approx: Boolean,
        withSymbol: Boolean
    ): String {
        return buildString {
            if (approx) append("≈ ")

            append("${tokenAmount.amount}")
            if (withSymbol) append(" ${formatToSymbol(tokenAmount)}")
        }
    }

    override fun formatToSymbol(
        tokenAmount: TokenAmountModel,
    ): String {
        return tokenAmount.appearance.symbol
    }

    override fun formatAmount(amount: BigDecimal, precision: RoundPrecision): String {
        return "$amount"
    }

    override fun formatPercent(value: Fraction): String {
        return "${value.inPercents} %"
    }

    override fun formatIntegralPercent(value: Fraction): String {
        return "${value.inPercents.intValueExact()} %"
    }
}
