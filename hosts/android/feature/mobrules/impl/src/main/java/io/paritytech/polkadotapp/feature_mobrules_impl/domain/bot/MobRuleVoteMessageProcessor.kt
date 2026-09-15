package io.paritytech.polkadotapp.feature_mobrules_impl.domain.bot

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import io.novasama.substrate_sdk_android.extensions.toHexString
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.toCustomContent
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatBotContext
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatBotMessageProcessor
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatMessage
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatMessageId
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.model.MobRuleCaseId
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.model.VoteCaseContext
import io.paritytech.polkadotapp.feature_mobrules_impl.domain.voting.VotingStateEvent
import io.paritytech.polkadotapp.feature_mobrules_impl.domain.voting.VotingStateNotifier
import io.paritytech.polkadotapp.feature_mobrules_impl.domain.voting.model.MobRuleVote
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.model.CaseType
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.model.MobRuleVotedCaseContent
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.model.UserVoteType
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.model.toVoteStringRes
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.renderer.MobRuleVotedCaseMessageRenderer
import kotlinx.coroutines.launch
import javax.inject.Inject

private data class PendingVoteMessage(
    val textMessageId: ChatMessageId,
    val cardMessageId: ChatMessageId
)

class MobRuleVoteMessageProcessor @Inject constructor(
    private val votingStateNotifier: VotingStateNotifier,
    private val caseStatusMessageProcessor: MobRuleCaseStatusMessageProcessor,
    @ApplicationContext private val context: Context,
) : ChatBotMessageProcessor {
    private val pendingMessages = mutableMapOf<MobRuleCaseId, PendingVoteMessage>()

    context(chatBotContext: ChatBotContext)
    override fun launchSendingMessages() {
        chatBotContext.scope.launch {
            votingStateNotifier.observeState().collect { event ->
                when (event) {
                    is VotingStateEvent.ReadyToVote -> Unit
                    is VotingStateEvent.Started -> onVoteStarted(event.vote, event.caseContext)
                    is VotingStateEvent.Completed -> onVoteCompleted(event.vote, event.caseContext)
                    is VotingStateEvent.Failed -> onVoteFailed(event.caseContext)
                }
            }
        }
    }

    context(chatBotContext: ChatBotContext)
    private suspend fun onVoteStarted(vote: MobRuleVote, caseContext: VoteCaseContext) {
        val caseId = caseContext.caseId
        if (caseId in pendingMessages) return

        val cardMessage = sendVotedCaseCardMessage(caseContext)
        val textMessage = sendPendingVoteTextMessage(vote)

        pendingMessages[caseId] = PendingVoteMessage(
            textMessageId = textMessage.id,
            cardMessageId = cardMessage.id
        )
    }

    context(chatBotContext: ChatBotContext)
    private suspend fun onVoteCompleted(vote: MobRuleVote, caseContext: VoteCaseContext) {
        pendingMessages.remove(caseContext.caseId) ?: return

        val userVoteType = vote.toUserVoteType()
        if (userVoteType != null) {
            caseStatusMessageProcessor.sendInitialStatusAndTrack(caseContext.caseId, userVoteType)
        }
    }

    context(chatBotContext: ChatBotContext)
    private suspend fun onVoteFailed(caseContext: VoteCaseContext) {
        val ids = pendingMessages.remove(caseContext.caseId) ?: return
        chatBotContext.removeMessage(ids.textMessageId)
        chatBotContext.removeMessage(ids.cardMessageId)
    }

    private fun MobRuleVote.toUserVoteType(): UserVoteType? {
        return when (this) {
            is MobRuleVote.Truth -> when (opinion) {
                MobRuleVote.TruthOpinion.True -> UserVoteType.TRUE
                MobRuleVote.TruthOpinion.False -> UserVoteType.FALSE
            }
            MobRuleVote.Contempt -> null
        }
    }

    context(chatBotContext: ChatBotContext)
    private suspend fun sendPendingVoteTextMessage(vote: MobRuleVote): ChatMessage {
        val voteText = context.getString(vote.toVoteStringRes())
        return chatBotContext.sendMessage(ChatMessage.Content.Text(voteText))
    }

    context(chatBotContext: ChatBotContext)
    private suspend fun sendVotedCaseCardMessage(caseContext: VoteCaseContext): ChatMessage {
        val content = when (caseContext) {
            is VoteCaseContext.Photo -> MobRuleVotedCaseContent(
                caseId = caseContext.caseId.toString(),
                caseType = CaseType.PHOTO,
                evidenceHashHex = caseContext.evidenceHash?.value?.toHexString(withPrefix = false),
                tattooId = caseContext.tattooId.toCustomContent(),
                tattooFamilyIdHex = caseContext.tattooFamilyId.value.toHexString(withPrefix = false)
            )
            is VoteCaseContext.Video -> MobRuleVotedCaseContent(
                caseId = caseContext.caseId.toString(),
                caseType = CaseType.VIDEO,
                evidenceHashHex = caseContext.evidenceHash?.value?.toHexString(withPrefix = false),
                tattooId = caseContext.tattooId.toCustomContent(),
                tattooFamilyIdHex = caseContext.tattooFamilyId.value.toHexString(withPrefix = false)
            )
        }
        return chatBotContext.sendCustomMessage(
            content = content,
            rendererId = MobRuleVotedCaseMessageRenderer.ID,
        )
    }
}
