package io.paritytech.polkadotapp.feature_become_citizen_impl.domain.bot

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import io.paritytech.polkadotapp.chains.multiNetwork.KnownChains
import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import io.paritytech.polkadotapp.feature_become_citizen_api.data.repository.TattooRepository
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.TattooProgressState
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.candidateState.TattooProgressStateUseCase
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.EvidenceType
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooFamilyMetadata
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooId
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.toCustomContent
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.storage.EvidenceLocalStateStorage
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.evidences.models.EvidenceLocalState
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.model.EvidenceProvidedContent
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.model.SelectedTattooContent
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.tattoo.InstructionsAttachmentUseCase
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.bot.renderers.SelectedTattooRenderer
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.bot.renderers.evidence.EvidenceProvidedMessageRenderer
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatBotContext
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatBotMessageProcessor
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.messageWasSent
import io.paritytech.polkadotapp.feature_chats_api.domain.model.Attachment
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatMessage
import io.paritytech.polkadotapp.feature_chats_api.domain.model.filterCustomContents
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.coroutines.flow.onEach
import javax.inject.Inject
import io.paritytech.polkadotapp.common.R as RCommon

class TattooProgressMessageProcessor @Inject constructor(
    @param:ApplicationContext private val context: Context,
    private val knownChains: KnownChains,
    private val tattooRepository: TattooRepository,
    private val tattooProgressStateUseCase: TattooProgressStateUseCase,
    private val instructionsAttachmentUseCase: InstructionsAttachmentUseCase,
    private val evidenceLocalStateStorage: EvidenceLocalStateStorage
) : ChatBotMessageProcessor {
    context(chatBotContext: ChatBotContext)
    override fun launchSendingMessages() {
        tattooProgressStateUseCase.tattooProgressStateFlow()
            .mapNotNull { it.getOrNull() }
            .onEach { handleProgress(it) }
            .launchIn(chatBotContext.scope)

        launchEvidenceProvidedMessages()
    }

    context(chatBotContext: ChatBotContext)
    private fun launchEvidenceProvidedMessages() {
        subscribeEvidenceStateUpdates(EvidenceType.PHOTO)

        subscribeEvidenceStateUpdates(EvidenceType.VIDEO) {
            val message = createTextMessage(RCommon.string.chat_bot_tattoo_after_video_evidence_provided)
            chatBotContext.sendMessage(message)
        }
    }

    context(chatBotContext: ChatBotContext)
    private suspend fun handleProgress(state: TattooProgressState) {
        when (state) {
            is TattooProgressState.Committed -> handleCommitedState(state)
            else -> Unit
        }
    }

    context(chatBotContext: ChatBotContext)
    private suspend fun handleCommitedState(state: TattooProgressState.Committed) {
        if (messageWasSent<SelectedTattooContent>()) return

        sendCommitedMessage(state)
    }

    context(chatBotContext: ChatBotContext)
    private suspend fun sendCommitedMessage(state: TattooProgressState.Committed) {
        val tattooId = state.tattooId
        val familyIndex = tattooId.familyIndex
        val tattooFamilyId = tattooRepository
            .getDesignFamily(knownChains.people, familyIndex)
            .map { it?.id }
            .getOrNull() ?: return

        val metadata = tattooRepository.getTattooFamilyMetadata(tattooFamilyId)
            .getOrNull() ?: return

        val customContent = SelectedTattooContent(
            tattooId = tattooId.toCustomContent(),
            tattooFamilyId = tattooFamilyId.toDataByteArray(),
            tattooFamilyName = metadata.name
        )

        chatBotContext.sendCustomMessage(
            rendererId = SelectedTattooRenderer.ID,
            content = customContent,
        )

        buildAfterCommitmentMessages(tattooId, tattooFamilyId, metadata)
            .forEach { message ->
                chatBotContext.sendMessage(message)
            }
    }

    private suspend fun buildAfterCommitmentMessages(
        tattooId: TattooId,
        familyId: ByteArray,
        metadata: TattooFamilyMetadata?
    ) = listOf(
        createTextMessage(RCommon.string.chat_bot_tattoo_after_commitment_message_1),
        createTextMessage(RCommon.string.chat_bot_tattoo_after_commitment_message_2),
        createPdfMessageWithInstructions(tattooId, familyId, metadata),
        createTextMessage(RCommon.string.chat_bot_tattoo_after_commitment_message_4),
        createTextMessage(RCommon.string.chat_bot_tattoo_after_commitment_message_5)
    )

    private suspend fun createPdfMessageWithInstructions(
        tattooId: TattooId,
        familyId: ByteArray,
        metadata: TattooFamilyMetadata?
    ): ChatMessage.Content {
        val instructionsFile = instructionsAttachmentUseCase.prepareInstructionsFile(tattooId, familyId, metadata)

        return ChatMessage.Content.RichText(
            text = context.getString(RCommon.string.chat_bot_tattoo_after_commitment_message_3),
            attachments = listOf(
                Attachment.file(
                    uri = instructionsFile.uri,
                    fileName = instructionsAttachmentUseCase.getInstructionsFileName(tattooId, metadata),
                    mimeType = instructionsFile.mimeType,
                    size = instructionsFile.size
                )
            )
        )
    }

    private fun createTextMessage(textRes: Int) = ChatMessage.Content.Text(context.getString(textRes))

    context(chatBotContext: ChatBotContext)
    private suspend fun sendEvidenceProvidedMessage(evidenceType: EvidenceType): Boolean {
        val isAlreadySent = chatBotContext.getPersistedMessages()
            .filterCustomContents<EvidenceProvidedContent>()
            .any { it.type == evidenceType }

        if (isAlreadySent) return false

        val customContent = EvidenceProvidedContent(evidenceType)

        chatBotContext.sendCustomMessage(
            rendererId = EvidenceProvidedMessageRenderer.ID,
            content = customContent,
        )

        return true
    }

    context(chatBotContext: ChatBotContext)
    private fun subscribeEvidenceStateUpdates(
        evidenceType: EvidenceType,
        onMessageSent: (suspend () -> Unit)? = null
    ) {
        evidenceLocalStateStorage
            .subscribeState(evidenceType)
            .onEach { state ->
                if (state == EvidenceLocalState.CONFIRMED) {
                    val isMessageSent = sendEvidenceProvidedMessage(evidenceType)
                    if (isMessageSent) {
                        onMessageSent?.invoke()
                    }
                }
            }
            .launchIn(chatBotContext.scope)
    }
}
