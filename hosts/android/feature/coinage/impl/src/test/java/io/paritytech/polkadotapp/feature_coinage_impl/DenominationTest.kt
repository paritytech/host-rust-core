package io.paritytech.polkadotapp.feature_coinage_impl

import io.paritytech.polkadotapp.feature_coinage_api.domain.common.CoinAmountBreakdown
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.ValueExponent
import io.paritytech.polkadotapp.feature_coinage_impl.common.centsToDollar
import io.paritytech.polkadotapp.feature_coinage_impl.common.coinageTestPrecision
import io.paritytech.polkadotapp.feature_coinage_impl.common.testConversionContext
import io.paritytech.polkadotapp.feature_coinage_impl.domain.common.RealCoinAmountBreakdownContext
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test

class DenominationTest {
    private val allowedExponents = (-2..7).map { ValueExponent(it) }.toSet()
    private val coinAmountBreakdown: CoinAmountBreakdown = RealCoinAmountBreakdownContext(coinageTestPrecision, testConversionContext, allowedExponents)

    @Test
    fun `should breakdown exact powers of 2`() {
        testBreakdown(input = 128.0, expected = listOf(7))
        testBreakdown(input = 64.0, expected = listOf(6))
        testBreakdown(input = 32.0, expected = listOf(5))
        testBreakdown(input = 16.0, expected = listOf(4))
        testBreakdown(input = 8.0, expected = listOf(3))
        testBreakdown(input = 4.0, expected = listOf(2))
        testBreakdown(input = 2.0, expected = listOf(1))
        testBreakdown(input = 1.0, expected = listOf(0))
        testBreakdown(input = 0.5, expected = listOf(-1))
        testBreakdown(input = 0.25, expected = listOf(-2))
    }

    @Test
    fun `should breakdown combinations of powers`() {
        testBreakdown(input = 18.5, expected = listOf(4, 1, -1))

        testBreakdown(input = 0.75, expected = listOf(-1, -2))

        testBreakdown(input = 255.75, expected = listOf(7, 6, 5, 4, 3, 2, 1, 0, -1, -2))
    }

    @Test
    fun `should use multiple max denominations for huge numbers`() {
        testBreakdown(input = 256.0, expected = listOf(7, 7))

        testBreakdown(input = 130.0, expected = listOf(7, 1))
    }

    @Test
    fun `should return empty list for zero input`() {
        testBreakdown(input = 0.0, expected = emptyList())
    }

    @Test(expected = Exception::class)
    fun `should crash when input is not a multiple of min exponent`() {
        testBreakdown(0.1, emptyList())
    }

    @Test(expected = Exception::class)
    fun `should crash when input is not a multiple of min exponent 2`() {
        testBreakdown(16.3, listOf(4, -2))
    }

    private fun testBreakdown(input: Double, expected: List<Int>) = runBlocking {
        val denominations = coinAmountBreakdown.breakdown(input.centsToDollar())
            .map { it.value }

        assertEquals(expected, denominations)
    }
}
