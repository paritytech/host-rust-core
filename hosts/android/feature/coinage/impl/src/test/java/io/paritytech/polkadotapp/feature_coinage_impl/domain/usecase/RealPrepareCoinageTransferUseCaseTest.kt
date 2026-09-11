package io.paritytech.polkadotapp.feature_coinage_impl.domain.usecase

import io.paritytech.polkadotapp.feature_coinage_api.domain.model.Coin
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.StrategyType
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.TransferPlan
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.ValueExponent
import io.paritytech.polkadotapp.feature_coinage_impl.domain.planner.TransferPlanner
import io.paritytech.polkadotapp.feature_coinage_impl.domain.planner.TransferPlannerFactory
import io.paritytech.polkadotapp.feature_coinage_impl.domain.planner.exceptions.InsufficientBalanceException
import io.paritytech.polkadotapp.feature_coinage_impl.domain.recycling.CoinageAssetSelector
import io.paritytech.polkadotapp.feature_coinage_impl.domain.recycling.SpendScope
import io.paritytech.polkadotapp.test_shared.any
import io.paritytech.polkadotapp.test_shared.eq
import io.paritytech.polkadotapp.test_shared.whenever
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mockito.Mockito.mock
import org.mockito.Mockito.never
import org.mockito.Mockito.verify
import java.math.BigDecimal

/**
 * Backs both the send and the running plan preview, so it has to reach the funds a confirmed send may use —
 * and no further than it must, or a transfer that never needed the offer spends privacy for nothing.
 */
class RealPrepareCoinageTransferUseCaseTest {
    private val planner: TransferPlanner = mock()
    private val plannerFactory: TransferPlannerFactory = mock()
    private val assetSelector: CoinageAssetSelector = mock()

    private val useCase = RealPrepareCoinageTransferUseCase(
        assetSelector = assetSelector,
        plannerFactory = plannerFactory,
        exactMatchStrategyFactory = mock(),
        splitStrategyFactory = mock(),
        unloadAndSplitStrategyFactory = mock(),
        chainAssetProvider = mock(),
        activePeopleCollectionUseCase = mock(),
        memoBuilder = mock(),
    )

    private val amount: BigDecimal = BigDecimal.TEN
    private val plan = TransferPlan(StrategyType.ExactCoins(coins = emptyList()))

    // One instance each: Coin equality runs through the mocked accountId, so two "identical" coins differ.
    private val spendableCoin = coinOf(derivationIndex = 1)
    private val heldForPrivacy = coinOf(derivationIndex = 2)

    private val spendableOnly = listOf(spendableCoin)
    private val widened = listOf(spendableCoin, heldForPrivacy)

    @Test
    fun `an amount the spendable funds cover is never planned against the wider set`() = runBlocking<Unit> {
        withPlanner()
        withScopes()
        whenever(planner.plan(eq(amount), eq(spendableOnly), any())).thenReturn(Result.success(plan))

        assertEquals(plan, useCase.preparePlan(amount).getOrNull())

        verify(planner, never()).plan(eq(amount), eq(widened), any())
    }

    @Test
    fun `an amount the spendable funds cannot cover falls back to the wider set`() = runBlocking<Unit> {
        withPlanner()
        withScopes()
        whenever(planner.plan(eq(amount), eq(spendableOnly), any())).thenReturn(failure())
        whenever(planner.plan(eq(amount), eq(widened), any())).thenReturn(Result.success(plan))

        assertEquals(plan, useCase.preparePlan(amount).getOrNull())
    }

    @Test
    fun `neither set covering the amount fails`() = runBlocking<Unit> {
        withPlanner()
        withScopes()
        whenever(planner.plan(eq(amount), any(), any())).thenReturn(failure())

        assertTrue(useCase.preparePlan(amount).isFailure)
    }

    @Test
    fun `no planner means no plan`() = runBlocking<Unit> {
        withScopes()
        whenever(plannerFactory.create()).thenReturn(failure())

        assertTrue(useCase.preparePlan(amount).isFailure)

        verify(planner, never()).plan(any(), any(), any())
    }

    private suspend fun withPlanner() {
        whenever(plannerFactory.create()).thenReturn(Result.success(planner))
    }

    private suspend fun withScopes() {
        whenever(assetSelector.getSelectableCoinsByScope()).thenReturn(
            mapOf(SpendScope.SPENDABLE to spendableOnly, SpendScope.WITH_CONFIRMATION to widened)
        )
        whenever(assetSelector.getSelectableVouchersByScope()).thenReturn(
            SpendScope.entries.associateWith { emptyList() }
        )
    }

    private fun <T> failure(): Result<T> = Result.failure(InsufficientBalanceException())

    private fun coinOf(derivationIndex: Int) = Coin(
        derivationIndex = derivationIndex,
        valueExponent = ValueExponent(1),
        age = Coin.Age.Known(3),
        isOnChain = true,
        accountId = mock(),
    )
}
