package io.paritytech.polkadotapp.feature_chats_impl.domain.models

import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatId
import io.paritytech.polkadotapp.feature_chats_api.domain.model.productRoomId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

private const val EXTENSION = "dim2.dot"
private const val ROOM = "jollity"

class ChatIdProductRoomIdTest {
    @Test
    fun `a named product room yields its sub room id`() {
        val chatId = ChatId.forExtensionRoom(EXTENSION, ROOM)

        assertEquals(ROOM, chatId.productRoomId())
    }

    @Test
    fun `a product default chat has no room`() {
        val chatId = ChatId.forExtension(EXTENSION)

        assertNull(chatId.productRoomId())
    }

    @Test
    fun `a contact chat has no product room`() {
        val chatId = ChatId.fromRawValue(ByteArray(32) { 7 })

        assertNull(chatId.productRoomId())
    }

    @Test
    fun `an empty sub room is treated as no room`() {
        val chatId = ChatId.forExtensionRoom(EXTENSION, "")

        assertNull(chatId.productRoomId())
    }
}
