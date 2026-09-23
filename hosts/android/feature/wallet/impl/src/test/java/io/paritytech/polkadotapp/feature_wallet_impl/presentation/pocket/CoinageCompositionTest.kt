package io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket

import io.paritytech.polkadotapp.chains.network.binding.Balance
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.CoinageBalance
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.mapper.clearing
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.mapper.toCompositionUiModel
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.models.CoinageCompositionUiModel
import org.junit.Assert.assertEquals
import org.junit.Test
import java.math.BigInteger

private const val TOLERANCE = 0.0001f

class CoinageCompositionTest {
    @Test
    fun `clearing folds gaining privacy and pending together`() {
        val balance = balanceOf(ready = 50, gainingPrivacy = 30, pending = 20)

        assertEquals(balanceOf(50), balance.clearing)
    }

    @Test
    fun `ready and clearing partition the bar`() {
        val composition = balanceOf(ready = 50, gainingPrivacy = 30, pending = 20).toCompositionUiModel()

        assertEquals(0.5f, composition.readyFraction, TOLERANCE)
        assertEquals(0.5f, composition.clearingFraction, TOLERANCE)
    }

    @Test
    fun `nothing held is the empty bar`() {
        val composition = balanceOf(ready = 0, gainingPrivacy = 0, pending = 0).toCompositionUiModel()

        assertEquals(CoinageCompositionUiModel.EMPTY, composition)
    }

    private fun balanceOf(ready: Long, gainingPrivacy: Long, pending: Long) = CoinageBalance(
        availablePrivate = balanceOf(ready),
        gainingPrivacy = CoinageBalance.GainingPrivacyBalance(balanceOf(gainingPrivacy), canSpendWithConfirmation = true),
        pending = balanceOf(pending),
    )

    private fun balanceOf(amount: Long) = Balance(BigInteger.valueOf(amount))
}
