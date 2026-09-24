package io.paritytech.polkadotapp.feature_products_impl.domain.bot

import android.content.Context
import io.mockk.every
import io.mockk.mockk
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.feature_chats_api.domain.extension.ChatExtensionContext
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatId
import io.paritytech.polkadotapp.feature_products_api.model.Product
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_products_api.model.toChatExtensionId
import io.paritytech.polkadotapp.feature_products_impl.domain.bot.e2e.E2EPendingChatMessages
import io.paritytech.polkadotapp.feature_products_impl.domain.truapi.ROOM_HOST
import io.paritytech.polkadotapp.feature_products_impl.domain.worker.ProductWorker
import io.paritytech.polkadotapp.feature_products_impl.domain.worker.ProductWorkerRefCounter
import io.paritytech.polkadotapp.feature_products_impl.domain.worker.ProductWorkerReference
import io.paritytech.polkadotapp.feature_products_impl.domain.worker.RecordingWorker
import io.paritytech.polkadotapp.feature_products_impl.domain.worker.WorkerModalityApi
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

private const val ROOM = "truapi-playground"
private const val MESSAGE = "!diagnose"

class ProductChatExtensionTest {
    private val product = Product(ProductId.fromStoredValue("truapi-playground.dot"), "TrUAPI Playground", icon = null)
    private val extensionId = product.id.toChatExtensionId()

    private class FakeRefCounter(private val booted: ProductWorker) : ProductWorkerRefCounter {
        var chatSurface: ProductChatMessaging? = null

        override suspend fun acquire(productId: ProductId, label: String): ProductWorkerReference {
            return object : ProductWorkerReference {
                override suspend fun worker(): ProductWorker = booted
                override suspend fun enableModalityApi(api: WorkerModalityApi) {
                    chatSurface = (api as WorkerModalityApi.Chat).messaging
                }

                override fun release() = Unit
            }
        }

        override fun chatMessaging(productId: ProductId): ProductChatMessaging = FakeChatMessaging()
    }

    private fun TestScope.pendingMessages() =
        E2EPendingChatMessages(CoroutineScope(StandardTestDispatcher(testScheduler)))

    private fun extensionWith(pending: E2EPendingChatMessages, refCounter: ProductWorkerRefCounter) =
        ProductChatExtension(
            appContext = mockk<Context>(relaxed = true),
            product = product,
            workerRefCounter = refCounter,
            pendingE2EMessages = pending,
        )

    private fun chatExtensionContext(scope: CoroutineScope, ownRooms: Flow<List<ChatId>>): ChatExtensionContext {
        val computationalScope = object : ComputationalScope, CoroutineScope by scope {}

        return mockk<ChatExtensionContext>(relaxed = true).also {
            every { it.scope } returns computationalScope
            every { it.subscribeNewMessages(any(), any()) } returns emptyFlow()
            every { it.subscribeOwnRooms() } returns ownRooms
        }
    }

    private fun TestScope.withChatHost(
        ownRooms: Flow<List<ChatId>> = emptyFlow(),
        block: context(ChatExtensionContext) (CoroutineScope) -> Unit,
    ) {
        val hostScope = CoroutineScope(StandardTestDispatcher(testScheduler))
        try {
            with(chatExtensionContext(hostScope, ownRooms)) { block(hostScope) }
            advanceUntilIdle()
        } finally {
            hostScope.cancel()
        }
    }

    @Test
    fun `a queued message is delivered once the worker has booted`() = runTest {
        val worker = RecordingWorker()
        val pending = pendingMessages().apply { queue(product.id, roomId = ROOM, text = MESSAGE) }

        withChatHost { extensionWith(pending, FakeRefCounter(worker)).startGlobalWork() }

        assertEquals(listOf<Pair<String?, String>>(ROOM to MESSAGE), worker.delivered)
    }

    @Test
    fun `a restarted extension for the same product does not redeliver`() = runTest {
        val worker = RecordingWorker()
        val pending = pendingMessages().apply { queue(product.id, roomId = ROOM, text = MESSAGE) }

        withChatHost { extensionWith(pending, FakeRefCounter(worker)).startGlobalWork() }
        withChatHost { extensionWith(pending, FakeRefCounter(worker)).startGlobalWork() }

        assertEquals(1, worker.delivered.size)
    }

    @Test
    fun `the roomless default chat is not a product room`() = runTest {
        val refCounter = FakeRefCounter(RecordingWorker())
        val ownRooms = flowOf(listOf(ChatId.forExtension(extensionId), ChatId.forExtensionRoom(extensionId, ROOM)))

        withChatHost(ownRooms) { extensionWith(pendingMessages(), refCounter).startGlobalWork() }

        val rooms = requireNotNull(refCounter.chatSurface).subscribeChatRooms().first()
        assertEquals(listOf(ROOM to ROOM_HOST), rooms.map { it.roomId to it.participatingAs })
    }
}
