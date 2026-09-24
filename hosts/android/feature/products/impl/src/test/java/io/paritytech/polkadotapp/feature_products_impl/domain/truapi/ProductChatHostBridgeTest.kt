package io.paritytech.polkadotapp.feature_products_impl.domain.truapi

import io.paritytech.polkadotapp.feature_chats_api.domain.extension.CreateRoomStatus
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatId
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_products_impl.domain.bot.FakeChatMessaging
import io.paritytech.polkadotapp.feature_products_impl.domain.bot.model.CreateProductRoomResult
import io.paritytech.polkadotapp.feature_products_impl.domain.bot.model.ProductChatIdParameter
import io.paritytech.polkadotapp.feature_products_impl.domain.bot.model.ProductChatRoom
import io.paritytech.polkadotapp.feature_products_impl.domain.bot.model.toChatId
import io.paritytech.polkadotapp.feature_products_impl.domain.jsEngine.HostCallException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import uniffi.truapi.ChatMessageContent
import uniffi.truapi.ChatReaction
import uniffi.truapi.ChatRoomParticipation
import uniffi.truapi.ChatRoomRegistrationStatus
import uniffi.truapi_server.HostRejection
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds
import kotlin.time.measureTime

private const val MESSAGING_NOT_SUPPORTED_CODE = "messaging_not_supported"
private const val ROOM = "jollity"

class ProductChatHostBridgeTest {

    private val productId = ProductId.fromStoredValue("dim2.dot")
    private val workerScope = CoroutineScope(Dispatchers.Default)

    @After
    fun tearDown() = workerScope.cancel()

    @Test
    fun `a text message is posted to the room the core names`() {
        val api = FakeChatMessaging(onSendMessage = { _, _ -> Result.success("message-id") })
        val bridge = bridge(api)

        bridge.postMessage(ROOM, ChatMessageContent.Text("hi"))

        assertEquals(listOf(ROOM to "hi"), api.sentText)
    }

    @Test
    fun `an empty room id addresses the product's default chat`() {
        val api = FakeChatMessaging(onSendMessage = { _, _ -> Result.success("message-id") })
        val bridge = bridge(api)

        bridge.postMessage("", ChatMessageContent.Text("hi"))

        val addressed = ProductChatIdParameter(api.sentText.single().first).toChatId(productId.value)
        assertEquals(ChatId.forExtension(productId.value), addressed)
    }

    @Test
    fun `an unsupported content variant is rejected by name`() {
        val api = FakeChatMessaging()
        val bridge = bridge(api)

        val thrown = runCatching {
            bridge.postMessage(ROOM, ChatMessageContent.Reaction(reaction()))
        }.exceptionOrNull()

        assertTrue(thrown is HostRejection)
        assertTrue(thrown!!.message!!.contains("Reaction"))
        assertTrue(api.sentText.isEmpty())
    }

    @Test
    fun `registerBot is rejected — this host has no bot registry`() {
        val bridge = bridge(FakeChatMessaging())

        assertTrue(runCatching { bridge.registerBot("b", "B", "") }.exceptionOrNull() is HostRejection)
    }

    @Test
    fun `an unbound surface refuses to list rooms at once, without spending the budget`() {
        val bridge = bridge(FakeChatMessaging(), callTimeout = 10.seconds)

        lateinit var thrown: Throwable
        val elapsed = measureTime { thrown = runCatching { bridge.listRooms() }.exceptionOrNull()!! }

        assertTrue(thrown is HostRejection)
        assertTrue(thrown.message!!.contains("no chat surface is bound"))
        assertTrue("expected an immediate answer, took $elapsed", elapsed < 1.seconds)
    }

    @Test
    fun `a failing createRoom is refused, not reported as may still`() {
        val bridge = bridge(FakeChatMessaging(onCreateRoom = { messagingNotSupported() }))

        val thrown = runCatching { bridge.createRoom(ROOM, "Jollity", "icon") }.exceptionOrNull()

        assertTrue(thrown is HostRejection)
        assertTrue(thrown!!.message!!.contains("refused"))
        assertFalse(thrown.message!!.contains("may still"))
    }

    @Test
    fun `a loading room list times out rather than reporting no rooms`() {
        val bridge = bridge(FakeChatMessaging(rooms = flow { awaitCancellation() }))

        val thrown = runCatching { bridge.listRooms() }.exceptionOrNull()

        assertTrue(thrown is HostRejection)
        assertTrue(thrown!!.message!!.contains("may still"))
    }

    @Test
    fun `a timeout rejects, and says the send may still have landed`() {
        val bridge = bridge(FakeChatMessaging(onSendMessage = { _, _ -> awaitCancellation() }))

        val thrown = runCatching {
            bridge.postMessage(ROOM, ChatMessageContent.Text("hi"))
        }.exceptionOrNull()

        assertTrue(thrown is HostRejection)
        assertTrue(thrown!!.message!!.contains("may still"))
    }

    @Test
    fun `listRooms maps the RoomHost and Bot participation strings to the core enum`() {
        val rooms = listOf(ProductChatRoom("room-1", ROOM_HOST), ProductChatRoom("room-2", BOT))
        val bridge = bridge(FakeChatMessaging(rooms = flowOf(rooms)))

        assertEquals(
            listOf(
                "room-1" to ChatRoomParticipation.ROOM_HOST,
                "room-2" to ChatRoomParticipation.BOT,
            ),
            bridge.listRooms().map { it.roomId to it.participatingAs },
        )
    }

    @Test
    fun `listRooms refuses on an unrecognised participation value`() {
        val bridge = bridge(FakeChatMessaging(rooms = flowOf(listOf(ProductChatRoom("room-1", "Ghost")))))

        val thrown = runCatching { bridge.listRooms() }.exceptionOrNull()

        assertTrue(thrown is HostRejection)
        assertTrue(thrown!!.message!!.contains("Ghost"))
    }

    @Test
    fun `createRoom maps New and Exists to the core registration status`() {
        fun statusFor(status: CreateRoomStatus) = bridge(
            FakeChatMessaging(onCreateRoom = { Result.success(CreateProductRoomResult(status)) }),
        ).createRoom(ROOM, "Jollity", "icon")

        assertEquals(ChatRoomRegistrationStatus.NEW, statusFor(CreateRoomStatus.New))
        assertEquals(ChatRoomRegistrationStatus.EXISTS, statusFor(CreateRoomStatus.Exists))
    }

    private fun bridge(
        api: FakeChatMessaging,
        callTimeout: Duration = 50.milliseconds,
    ) = ProductChatHostBridge(productId, api, workerScope, callTimeout = callTimeout)

    private fun reaction() = ChatReaction(messageId = "msg-1", emoji = "👍")
}

private fun <T> messagingNotSupported(): Result<T> = Result.failure(
    HostCallException(MESSAGING_NOT_SUPPORTED_CODE, "Product messaging is not supported in this context"),
)
