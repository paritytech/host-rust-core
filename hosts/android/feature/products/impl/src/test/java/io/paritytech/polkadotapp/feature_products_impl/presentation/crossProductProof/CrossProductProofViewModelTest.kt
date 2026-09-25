package io.paritytech.polkadotapp.feature_products_impl.presentation.crossProductProof

import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import io.paritytech.polkadotapp.feature_account_api.domain.derivation.DerivationIndex32
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_products_impl.domain.crossProductProof.CrossProductProofContext
import io.paritytech.polkadotapp.feature_products_impl.domain.crossProductProof.CrossProductProofContextHolder
import io.paritytech.polkadotapp.feature_products_impl.presentation.createAndClear
import io.paritytech.polkadotapp.feature_products_impl.presentation.productBotManagement.ProductsRouter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Before
import org.junit.Test
import org.mockito.Mockito.mock
import org.mockito.Mockito.times
import org.mockito.Mockito.verify

class CrossProductProofViewModelTest {
    private val testDispatcher = StandardTestDispatcher()
    private val router: ProductsRouter = mock()
    private val holder = CrossProductProofContextHolder()

    private val context = proofContext("lottery.dot")

    @Before
    fun setUp() = Dispatchers.setMain(testDispatcher)

    @After
    fun tearDown() = Dispatchers.resetMain()

    @Test
    fun `the proof prompt closes when it is withdrawn`() = runTest(testDispatcher) {
        CrossProductProofViewModel(router, context, holder)
        val caller = launch { context.awaitDecision {} }
        runCurrent()
        verifyPromptClosed(times = 0)

        caller.cancel()
        runCurrent()

        verifyPromptClosed(times = 1)
    }

    @Test
    fun `the proof prompt clears its own context when it goes away`() = runTest(testDispatcher) {
        holder.set(context)

        createAndClear { CrossProductProofViewModel(router, context, holder) }

        assertNull(holder.get())
    }

    @Test
    fun `a newer proof prompt's context survives when an older one goes away`() = runTest(testDispatcher) {
        val newer = proofContext("other.dot")
        holder.set(newer)

        createAndClear { CrossProductProofViewModel(router, context, holder) }

        assertSame(newer, holder.get())
    }

    private fun proofContext(callingProduct: String) = CrossProductProofContext(
        callingProduct = ProductId.fromStoredValue(callingProduct),
        onBehalfOf = ProductId.fromStoredValue("voting.dot"),
        suffix = DerivationIndex32.default(),
        message = byteArrayOf(1).toDataByteArray(),
    )

    private fun verifyPromptClosed(times: Int) = verify(router, times(times)).back()
}
