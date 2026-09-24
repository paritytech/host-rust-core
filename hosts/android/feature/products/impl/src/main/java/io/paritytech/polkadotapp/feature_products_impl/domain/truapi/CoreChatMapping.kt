package io.paritytech.polkadotapp.feature_products_impl.domain.truapi

import io.paritytech.polkadotapp.feature_products_impl.domain.bot.model.ProductChatRoom
import uniffi.truapi.ChatRoom
import uniffi.truapi.ChatRoomParticipation
import uniffi.truapi_server.HostRejection

internal fun ProductChatRoom.toCoreChatRoom(): ChatRoom = ChatRoom(
    roomId = roomId,
    participatingAs = participatingAs.toParticipation(),
)

internal const val ROOM_HOST = "RoomHost"
internal const val BOT = "Bot"

private fun String.toParticipation(): ChatRoomParticipation = when (this) {
    ROOM_HOST -> ChatRoomParticipation.ROOM_HOST
    BOT -> ChatRoomParticipation.BOT
    else -> throw HostRejection.Rejected("unknown chat room participation: $this")
}
