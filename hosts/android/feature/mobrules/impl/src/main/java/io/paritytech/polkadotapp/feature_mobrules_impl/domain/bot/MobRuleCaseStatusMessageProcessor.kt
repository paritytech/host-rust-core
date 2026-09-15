package io.paritytech.polkadotapp.feature_mobrules_impl.domain.bot

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatBotContext
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatBotMessageProcessor
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatMessage
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatMessageId
import io.paritytech.polkadotapp.feature_chats_api.domain.model.customContentOrNull
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.CaseObservation
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.MobRuleCasesRepository
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.model.MobRuleCaseId
import io.paritytech.polkadotapp.feature_mobrules_impl.domain.voting.matchesVerdict
import io.paritytech.polkadotapp.feature_mobrules_impl.domain.voting.model.MobRuleVote
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.model.CaseJudgmentStatus
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.model.MobRuleCaseStatusContent
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.model.UserVoteType
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.renderer.MobRuleCaseStatusMessageRenderer
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.coroutines.launch
import javax.inject.Inject

private data class ProcessingCase(
    val caseId: MobRuleCaseId,
    val messageId: ChatMessageId,
    val userVoteType: UserVoteType
)

class MobRuleCaseStatusMessageProcessor @Inject constructor(
    private val casesRepository: MobRuleCasesRepository,
    private val chainRegistry: ChainRegistry,
) : ChatBotMessageProcessor {
    context(chatBotContext: ChatBotContext)
    override fun launchSendingMessages() {
        chatBotContext.scope.launch {
            recoverPersistedProcessingCases()
        }
    }

    context(chatBotContext: ChatBotContext)
    internal suspend fun sendInitialStatusAndTrack(caseId: MobRuleCaseId, userVoteType: UserVoteType) {
        val content = MobRuleCaseStatusContent(caseId.toString(), CaseJudgmentStatus.PROCESSING, userVoteType)
        val message = chatBotContext.sendCustomMessage(content, MobRuleCaseStatusMessageRenderer.ID)
        chatBotContext.scope.launch {
            val chainId = chainRegistry.knownChains.people
            casesRepository.observeCaseUpdates(chainId, listOf(caseId))
                .mapNotNull { resolveJudgment(it, userVoteType) }
                .map { newStatus ->
                    val newContent = MobRuleCaseStatusContent(caseId.toString(), newStatus, userVoteType)
                    chatBotContext.modifyMessage(message.id, ChatMessage.Content.Custom(MobRuleCaseStatusMessageRenderer.ID, Result.success(newContent)))
                }
                .first()
        }
    }

    context(chatBotContext: ChatBotContext)
    private suspend fun recoverPersistedProcessingCases() {
        val messages = chatBotContext.getPersistedMessages()
        val processingCases = messages.mapNotNull { message ->
            val content = message.customContentOrNull<MobRuleCaseStatusContent>() ?: return@mapNotNull null
            if (content.status != CaseJudgmentStatus.PROCESSING) return@mapNotNull null
            val caseId = content.caseId.toBigIntegerOrNull() ?: return@mapNotNull null
            ProcessingCase(caseId, message.id, content.userVoteType)
        }
        if (processingCases.isEmpty()) return

        val chainId = chainRegistry.knownChains.people
        val caseIds = processingCases.map { it.caseId }
        val casesByKey = processingCases.associateBy { it.caseId }

        casesRepository.observeCaseUpdates(chainId, caseIds)
            .mapNotNull { observation ->
                val case = casesByKey.getValue(observation.caseId)
                resolveJudgment(observation, case.userVoteType)?.let { case to it }
            }
            .collect { (case, judgmentStatus) ->
                val newContent = MobRuleCaseStatusContent(case.caseId.toString(), judgmentStatus, case.userVoteType)
                chatBotContext.modifyMessage(case.messageId, ChatMessage.Content.Custom(MobRuleCaseStatusMessageRenderer.ID, Result.success(newContent)))
            }
    }

    private fun resolveJudgment(observation: CaseObservation, userVoteType: UserVoteType): CaseJudgmentStatus? {
        return when {
            observation.doneCase != null -> when (val verdict = observation.doneCase.verdict) {
                is MobRuleVote.Contempt -> null
                is MobRuleVote.Truth -> if (userVoteType.matchesVerdict(verdict)) CaseJudgmentStatus.CORRECT
                else CaseJudgmentStatus.INCORRECT
            }
            observation.openCase != null || observation.ripeCase != null -> null
            // All three null — combine may emit intermediate states during open→done chain transition. Keep waiting.
            else -> null
        }
    }
}
