package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.bot.renderers.evidence

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dagger.hilt.android.qualifiers.ApplicationContext
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.EvidenceType
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.model.EvidenceProvidedContent
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.bot.compose.EvidenceProvidedMessageContent
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.CustomChatMessageRenderer
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.MessageDrawingContext
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatMessage
import io.paritytech.polkadotapp.feature_chats_api.presentation.model.ChatMessageUiModel
import io.paritytech.polkadotapp.feature_chats_api.presentation.model.LastMessageUiModel
import javax.inject.Inject
import io.paritytech.polkadotapp.common.R as RCommon

class EvidenceProvidedMessageRenderer @Inject constructor(
    @param:ApplicationContext private val appContext: Context
) : CustomChatMessageRenderer<EvidenceProvidedContent> {
    companion object {
        const val ID = "EvidenceTattooRenderer"
    }

    override val id: String = ID

    override val contentSerializer = EvidenceProvidedContent.serializer()

    @Composable
    override fun DrawMessage(
        message: ChatMessageUiModel.Custom<EvidenceProvidedContent>,
        context: MessageDrawingContext
    ) {
        message.content
            .onSuccess { content ->
                EvidenceProvidedMessage(content.type)
            }
    }

    @Composable
    private fun EvidenceProvidedMessage(type: EvidenceType) {
        val viewModel = hiltViewModel<EvidenceProvidedMessageViewModel, EvidenceProvidedMessageViewModel.Factory>(
            key = "EvidenceProvidedMessageViewModel_$type",
            creationCallback = { factory -> factory.create(type) }
        )

        val messageState by viewModel.message.collectAsStateWithLifecycle()
        EvidenceProvidedMessageContent(message = messageState)
    }

    override suspend fun formatNotificationContent(message: ChatMessage.Content.Custom<EvidenceProvidedContent>): Result<String> {
        return message.content.map {
            when (it.type) {
                EvidenceType.PHOTO -> appContext.getString(RCommon.string.chat_last_message_evidence_photo_provided)
                EvidenceType.VIDEO -> appContext.getString(RCommon.string.chat_last_message_evidence_video_provided)
            }
        }
    }

    @Composable
    override fun formatChatPreview(message: LastMessageUiModel.Custom<EvidenceProvidedContent>): Result<String> {
        return message.content.map {
            when (it.type) {
                EvidenceType.PHOTO -> appContext.getString(RCommon.string.chat_last_message_evidence_photo_provided)
                EvidenceType.VIDEO -> appContext.getString(RCommon.string.chat_last_message_evidence_video_provided)
            }
        }
    }
}
