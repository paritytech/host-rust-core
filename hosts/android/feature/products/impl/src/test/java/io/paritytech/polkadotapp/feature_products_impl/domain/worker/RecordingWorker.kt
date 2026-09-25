package io.paritytech.polkadotapp.feature_products_impl.domain.worker

import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatMessageId
import io.paritytech.polkadotapp.feature_products_api.model.JsUiEvent
import io.paritytech.polkadotapp.feature_products_api.model.JsWidget
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow

class RecordingWorker(private val result: Result<Unit> = Result.success(Unit)) : ProductWorker {
    val delivered = mutableListOf<Pair<String?, String>>()
    val renderedRooms = mutableListOf<String?>()
    val events = mutableListOf<JsUiEvent>()

    override suspend fun onUserMessage(roomId: String?, text: String): Result<Unit> {
        delivered += roomId to text
        return result
    }

    override fun renderMessage(
        roomId: String?,
        messageId: ChatMessageId,
        messageType: String,
        messageData: DataByteArray,
    ): Flow<Result<JsWidget>> {
        renderedRooms += roomId
        return emptyFlow()
    }

    override fun dispatchEvent(event: JsUiEvent) {
        events += event
    }
}
