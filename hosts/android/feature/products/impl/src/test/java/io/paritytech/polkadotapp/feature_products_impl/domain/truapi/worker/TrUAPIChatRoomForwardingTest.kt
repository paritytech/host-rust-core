package io.paritytech.polkadotapp.feature_products_impl.domain.truapi.worker

import io.parity.truapi.TrUAPIProductExecution
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_products_impl.domain.bot.FakeChatMessaging
import io.paritytech.polkadotapp.feature_products_impl.domain.bot.model.ProductChatRoom
import io.paritytech.polkadotapp.feature_products_impl.domain.truapi.BOT
import io.paritytech.polkadotapp.feature_products_impl.domain.truapi.ROOM_HOST
import io.paritytech.polkadotapp.test_shared.any
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mockito.Mockito.inOrder
import org.mockito.Mockito.mock
import org.mockito.Mockito.never
import org.mockito.Mockito.times
import org.mockito.Mockito.verify
import org.mockito.Mockito.verifyNoInteractions
import uniffi.truapi.ChatRoom
import uniffi.truapi.ChatRoomParticipation

private const val ROOM_1 = "room-1"
private const val ROOM_2 = "room-2"

class TrUAPIChatRoomForwardingTest {
    private val productId = ProductId.fromStoredValue("chat.dot")
    private val execution: TrUAPIProductExecution = mock()

    private class Forwarding(val chatMessaging: FakeChatMessaging, val scope: CoroutineScope, val job: Job)

    private fun TestScope.forwarding(chatMessaging: FakeChatMessaging = FakeChatMessaging()): Forwarding {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val job = TrUAPIChatRoomForwarding(productId, execution, chatMessaging).start(scope)
        return Forwarding(chatMessaging, scope, job)
    }

    private fun emissions() = MutableSharedFlow<List<ProductChatRoom>>(extraBufferCapacity = 1)

    @Test
    fun `each room list emission reaches notifyChatRoomsChanged in order`() = runTest {
        val rooms = emissions()
        forwarding(FakeChatMessaging(rooms = rooms))
        runCurrent()

        rooms.tryEmit(listOf(ProductChatRoom(ROOM_1, ROOM_HOST)))
        runCurrent()
        rooms.tryEmit(listOf(ProductChatRoom(ROOM_1, ROOM_HOST), ProductChatRoom(ROOM_2, BOT)))
        runCurrent()

        val order = inOrder(execution)
        order.verify(execution).notifyChatRoomsChanged(listOf(ChatRoom(ROOM_1, ChatRoomParticipation.ROOM_HOST)))
        order.verify(execution).notifyChatRoomsChanged(
            listOf(
                ChatRoom(ROOM_1, ChatRoomParticipation.ROOM_HOST),
                ChatRoom(ROOM_2, ChatRoomParticipation.BOT),
            ),
        )
    }

    @Test
    fun `a bound surface with genuinely zero rooms pushes an empty list`() = runTest {
        forwarding(FakeChatMessaging(rooms = flowOf(emptyList())))
        runCurrent()

        verify(execution, times(1)).notifyChatRoomsChanged(emptyList())
    }

    @Test
    fun `forwarding stops when the worker's scope is cancelled`() = runTest {
        val rooms = emissions()
        val forwarding = forwarding(FakeChatMessaging(rooms = rooms))
        runCurrent()

        rooms.tryEmit(listOf(ProductChatRoom(ROOM_1, ROOM_HOST)))
        runCurrent()
        verify(execution, times(1)).notifyChatRoomsChanged(any())

        forwarding.scope.cancel()
        runCurrent()

        rooms.tryEmit(listOf(ProductChatRoom(ROOM_2, BOT)))
        runCurrent()

        verify(execution, times(1)).notifyChatRoomsChanged(any())
        verify(execution, never()).notifyChatRoomsChanged(listOf(ChatRoom(ROOM_2, ChatRoomParticipation.BOT)))
    }

    @Test
    fun `an unrecognised participation value is caught, not left to crash the scope`() = runTest {
        val rooms = emissions()
        val forwarding = forwarding(FakeChatMessaging(rooms = rooms))
        runCurrent()

        rooms.tryEmit(listOf(ProductChatRoom(ROOM_1, "Ghost")))
        runCurrent()

        assertTrue(forwarding.job.isActive)
        verify(execution, never()).notifyChatRoomsChanged(any())
    }

    @Test
    fun `forwarding re-resolves the chat slot and starts once it becomes bound later`() = runTest {
        val forwarding = forwarding()
        runCurrent()
        verifyNoInteractions(execution)

        forwarding.chatMessaging.rooms = MutableStateFlow(listOf(ProductChatRoom(ROOM_1, ROOM_HOST)))
        advanceUntilIdle()

        verify(execution, times(1)).notifyChatRoomsChanged(listOf(ChatRoom(ROOM_1, ChatRoomParticipation.ROOM_HOST)))
    }
}
