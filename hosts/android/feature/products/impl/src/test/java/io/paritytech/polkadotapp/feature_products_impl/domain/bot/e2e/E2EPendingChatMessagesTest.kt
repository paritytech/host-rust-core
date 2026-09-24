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
    fun `attaching a worker delivers the queued message with its room`() = runTest {
        val worker = RecordingWorker()

        queued().attach(product, worker)
        advanceUntilIdle()

        assertEquals(listOf<Pair<String?, String>>(ROOM to MESSAGE), worker.delivered)
    }

    @Test
    fun `a message queued while the worker is attached is delivered at once`() = runTest {
        val pending = holder()
        val worker = RecordingWorker()
        pending.attach(product, worker)

        pending.queue(product, ROOM, MESSAGE)
        advanceUntilIdle()

        assertEquals(listOf<Pair<String?, String>>(ROOM to MESSAGE), worker.delivered)
    }

    @Test
    fun `queueing never waits on the delivery`() = runTest {
        val pending = holder()
        val worker = RecordingWorker()
        pending.attach(product, worker)

        pending.queue(product, ROOM, MESSAGE)

        assertEquals(emptyList<Pair<String?, String>>(), worker.delivered)
        advanceUntilIdle()
        assertEquals(listOf<Pair<String?, String>>(ROOM to MESSAGE), worker.delivered)
    }

    @Test
    fun `a message queued after detach is parked for the next worker`() = runTest {
        val pending = holder()
        val detached = RecordingWorker()
        pending.attach(product, detached)
        pending.detach(product, detached)

        pending.queue(product, ROOM, MESSAGE)
        advanceUntilIdle()
        assertEquals(emptyList<Pair<String?, String>>(), detached.delivered)

        val next = RecordingWorker()
        pending.attach(product, next)
        advanceUntilIdle()
        assertEquals(listOf<Pair<String?, String>>(ROOM to MESSAGE), next.delivered)
    }

    @Test
    fun `a detach from the worker being replaced does not evict the new one`() = runTest {
        val pending = holder()
        val restarting = RecordingWorker()
        pending.attach(product, restarting)

        val next = RecordingWorker()
        pending.attach(product, next)
        pending.detach(product, restarting)

        pending.queue(product, ROOM, MESSAGE)
        advanceUntilIdle()

        assertEquals(listOf<Pair<String?, String>>(ROOM to MESSAGE), next.delivered)
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
