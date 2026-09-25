package io.paritytech.polkadotapp.feature_products_impl.domain.bot.e2e

import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_products_impl.domain.worker.RecordingWorker
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

private const val ROOM = "truapi-playground"
private const val MESSAGE = "!diagnose"

class E2EPendingChatMessagesTest {
    private val product = ProductId.fromStoredValue("truapi-playground.dot")

    private fun TestScope.holder() = E2EPendingChatMessages(CoroutineScope(StandardTestDispatcher(testScheduler)))

    private fun TestScope.queued() = holder().apply { queue(product, ROOM, MESSAGE) }

    @Test
    fun `a queue and an attach rendezvous in either order`() = runTest {
        val parked = RecordingWorker()
        queued().attach(product, parked)
        advanceUntilIdle()
        assertEquals(listOf<Pair<String?, String>>(ROOM to MESSAGE), parked.delivered)

        val pending = holder()
        val attached = RecordingWorker()
        pending.attach(product, attached)
        pending.queue(product, ROOM, MESSAGE)

        assertEquals(emptyList<Pair<String?, String>>(), attached.delivered)
        advanceUntilIdle()
        assertEquals(listOf<Pair<String?, String>>(ROOM to MESSAGE), attached.delivered)
    }

    @Test
    fun `a detach parks for the next worker, but a stale one does not evict it`() = runTest {
        val pending = holder()
        val detached = RecordingWorker()
        pending.attach(product, detached)
        pending.detach(product, detached)

        pending.queue(product, ROOM, MESSAGE)
        advanceUntilIdle()
        assertEquals(emptyList<Pair<String?, String>>(), detached.delivered)

        val next = RecordingWorker()
        pending.attach(product, next)
        pending.detach(product, detached)
        advanceUntilIdle()
        pending.queue(product, ROOM, MESSAGE)
        advanceUntilIdle()

        assertEquals(List(2) { ROOM to MESSAGE }, next.delivered)
    }

    @Test
    fun `a delivery cancelled by a worker restart is parked again, not lost`() = runTest {
        val pending = queued()
        pending.attach(product, RecordingWorker(Result.failure(CancellationException("worker disposed"))))
        advanceUntilIdle()

        val restarted = RecordingWorker()
        pending.attach(product, restarted)
        advanceUntilIdle()

        assertEquals(listOf<Pair<String?, String>>(ROOM to MESSAGE), restarted.delivered)
    }

    @Test
    fun `a failed delivery is swallowed, never thrown at the bot and never retried`() = runTest {
        val pending = queued()
        pending.attach(product, RecordingWorker(Result.failure(IllegalStateException("worker is gone"))))
        advanceUntilIdle()

        val restarted = RecordingWorker()
        pending.attach(product, restarted)
        advanceUntilIdle()

        assertEquals(emptyList<Pair<String?, String>>(), restarted.delivered)
    }
}
