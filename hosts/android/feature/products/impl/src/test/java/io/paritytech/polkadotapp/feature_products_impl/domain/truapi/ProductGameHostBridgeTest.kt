package io.paritytech.polkadotapp.feature_products_impl.domain.truapi

import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_products_impl.domain.gameReminders.GameReminderCenter
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertThrows
import org.junit.Test
import org.mockito.Mockito.inOrder
import org.mockito.Mockito.mock
import org.mockito.Mockito.verify
import org.mockito.Mockito.verifyNoInteractions
import uniffi.truapi_server.HostRejection

@OptIn(ExperimentalCoroutinesApi::class)
class ProductGameHostBridgeTest {
    private val productId = ProductId.fromStoredValue("jollity.dot")
    private val center: GameReminderCenter = mock()

    private fun TestScope.executionScope() = CoroutineScope(StandardTestDispatcher(testScheduler))

    @Test
    fun `schedule reaches the center with the execution's product and the start in milliseconds`() = runTest {
        val scope = executionScope()
        val bridge = ProductGameHostBridge(productId, center, scope)

        bridge.scheduleReminder(1_800_000_000_000uL)
        advanceUntilIdle()

        verify(center).schedule("jollity.dot", 1_800_000_000_000L)
        scope.cancel()
    }

    @Test
    fun `calls reach the center in the order the product made them`() = runTest {
        val scope = executionScope()
        val bridge = ProductGameHostBridge(productId, center, scope)

        bridge.scheduleReminder(1_800_000_000_000uL)
        bridge.cancelReminder()
        advanceUntilIdle()

        val order = inOrder(center)
        order.verify(center).schedule("jollity.dot", 1_800_000_000_000L)
        order.verify(center).cancel("jollity.dot")
        scope.cancel()
    }

    @Test
    fun `calls return before the center is reached`() = runTest {
        val scope = executionScope()
        val bridge = ProductGameHostBridge(productId, center, scope)

        bridge.scheduleReminder(1_800_000_000_000uL)

        verifyNoInteractions(center)
        scope.cancel()
    }

    @Test
    fun `calls after the execution scope ends are rejected`() = runTest {
        val scope = executionScope()
        val bridge = ProductGameHostBridge(productId, center, scope)

        scope.cancel()

        assertThrows(HostRejection::class.java) { bridge.scheduleReminder(1_800_000_000_000uL) }
        assertThrows(HostRejection::class.java) { bridge.cancelReminder() }
    }
}
