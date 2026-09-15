package io.paritytech.polkadotapp.feature_videogame_impl.domain.bot.statusProcessing

import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.domain.model.toTimestamp
import io.paritytech.polkadotapp.common.utils.mapToSet
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatBotContext
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatBotMessageProcessor
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatMessage
import io.paritytech.polkadotapp.feature_chats_api.domain.model.customContentOrNull
import io.paritytech.polkadotapp.feature_chats_api.domain.model.filterCustomContents
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.VideoGamesProgressUseCase
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.VideoGamesProgress
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.GamePlayersRepository
import io.paritytech.polkadotapp.feature_videogame_impl.domain.PlayerFrameFilePathCreator
import io.paritytech.polkadotapp.feature_videogame_impl.domain.bot.messages.gameResult.model.FailedPastGameScoring
import io.paritytech.polkadotapp.feature_videogame_impl.domain.bot.messages.gameResult.model.PastGameContent
import io.paritytech.polkadotapp.feature_videogame_impl.domain.bot.messages.gameResult.model.PastGameOutcome
import io.paritytech.polkadotapp.feature_videogame_impl.domain.bot.messages.gameResult.model.SuccessPastGameScoring
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGameJourneyItem
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.lastNonFutureGame
import io.paritytech.polkadotapp.feature_videogame_impl.domain.usecase.PlayingAccountUseCase
import io.paritytech.polkadotapp.feature_videogame_impl.domain.usecase.VideoGameJourneyUseCase
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.renderer.GameResultRenderer
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import javax.inject.Inject

private const val MAX_AVATAR_COUNT = 3

class GameStatusMessageProcessor @Inject constructor(
    private val gamesProgressUseCase: VideoGamesProgressUseCase,
    private val videoGameJourneyUseCase: VideoGameJourneyUseCase,
    private val gamePlayersRepository: GamePlayersRepository,
    private val playerFrameFilePathCreator: PlayerFrameFilePathCreator,
    private val playingAccountUseCase: PlayingAccountUseCase
) : ChatBotMessageProcessor {
    context(chatBotContext: ChatBotContext)
    override fun launchSendingMessages() {
        chatBotContext.scope.launch {
            videoGameJourneyUseCase()
                .collect { journeyItems -> processJourneyItems(journeyItems) }
        }
    }

    context(chatBotContext: ChatBotContext)
    private suspend fun processJourneyItems(journeyItems: List<VideoGameJourneyItem>) {
        val allExistingMessages = chatBotContext.getPersistedMessages()
        val fullyCompleted = allExistingMessages.fullyCompletedLookup()
        val messageByIndex = allExistingMessages.messageByIndexMapping()
        val ourPlayerAccountId = playingAccountUseCase.getOurPlayerAccountId()
        val alreadyAnnouncedPersonhood = allExistingMessages.hasAnnouncedPersonhood()

        journeyItems
            .filter { it.gameIndex !in fullyCompleted && it.status != VideoGameJourneyItem.Status.FUTURE }
            .onEach { item ->
                val existingMessage = messageByIndex[item.gameIndex]

                when (item.status) {
                    VideoGameJourneyItem.Status.PENDING -> if (existingMessage == null) {
                        sendNewPendingGameMessage(item, ourPlayerAccountId)
                    }

                    VideoGameJourneyItem.Status.SUCCESSFUL -> {
                        val canDetectPersonhoodProgress = canDetectPersonhoodProgress(item, journeyItems)
                        upsertSuccessGameMessage(item, canDetectPersonhoodProgress, alreadyAnnouncedPersonhood, existingMessage, ourPlayerAccountId)
                    }

                    VideoGameJourneyItem.Status.FAILED -> {
                        val canDetectPersonhoodProgress = canDetectPersonhoodProgress(item, journeyItems)
                        upsertFailedGameMessage(item, canDetectPersonhoodProgress, existingMessage, ourPlayerAccountId)
                    }

                    VideoGameJourneyItem.Status.FUTURE -> Unit
                }
            }
    }

    private fun List<ChatMessage>.fullyCompletedLookup(): Set<GameIndex> {
        return filterCustomContents<PastGameContent>()
            .filter { it.outcome !is PastGameOutcome.Pending }
            .mapToSet { it.gameIndex }
    }

    private fun List<ChatMessage>.messageByIndexMapping(): Map<GameIndex, ChatMessage> {
        return mapNotNull { message ->
            message.customContentOrNull<PastGameContent>()
                ?.let { it.gameIndex to message }
        }.toMap()
    }

    private fun List<ChatMessage>.hasAnnouncedPersonhood(): Boolean {
        val latestScoring = filterCustomContents<PastGameContent>()
            .mapNotNull { content -> (content.outcome as? PastGameOutcome.Success)?.scoring?.let { content.gameIndex to it } }
            .maxByOrNull { (gameIndex, _) -> gameIndex }
            ?.second

        return latestScoring is SuccessPastGameScoring.ReachedPersonhood || latestScoring is SuccessPastGameScoring.AlreadyReachedPersonhood
    }

    context(chatBotContext: ChatBotContext)
    private suspend fun sendNewPendingGameMessage(
        item: VideoGameJourneyItem,
        ourPlayerAccountId: AccountId,
    ) {
        val customContent = createNewPastGameContent(
            outcome = PastGameOutcome.Pending,
            gameJourneyItem = item,
            ourPlayerAccountId = ourPlayerAccountId
        )

        chatBotContext.sendCustomMessage(
            rendererId = GameResultRenderer.ID,
            content = customContent,
        )
    }

    context(chatBotContext: ChatBotContext)
    private suspend fun upsertSuccessGameMessage(
        item: VideoGameJourneyItem,
        canDetectPersonhoodProgress: Boolean,
        alreadyAnnouncedPersonhood: Boolean,
        existingMessage: ChatMessage?,
        ourPlayerAccountId: AccountId
    ) {
        val content = constructSuccessMessageContent(
            item,
            canDetectPersonhoodProgress,
            alreadyAnnouncedPersonhood,
            existingMessage,
            ourPlayerAccountId
        )
        chatBotContext.upsertMessage(existingMessage?.id, content)
    }

    context(chatBotContext: ChatBotContext)
    private suspend fun upsertFailedGameMessage(
        item: VideoGameJourneyItem,
        canDetectPersonhoodProgress: Boolean,
        existingMessage: ChatMessage?,
        ourPlayerAccountId: AccountId
    ) {
        val content = constructFailedMessageContent(item, canDetectPersonhoodProgress, existingMessage, ourPlayerAccountId)
        chatBotContext.upsertMessage(existingMessage?.id, content)
    }

    context(scope: ComputationalScope)
    private suspend fun constructSuccessMessageContent(
        gameJourneyItem: VideoGameJourneyItem,
        canDetectPersonhoodProgress: Boolean,
        alreadyAnnouncedPersonhood: Boolean,
        existingMessage: ChatMessage?,
        ourPlayerAccountId: AccountId,
    ): ChatMessage.Content {
        val outcome = if (canDetectPersonhoodProgress) {
            val gameProgress = gamesProgressUseCase.awaitStateForSuccessGame()
            PastGameOutcome.Success(gameProgress.toSuccessPastGameScoringState(alreadyAnnouncedPersonhood))
        } else {
            val gameProgress = gamesProgressUseCase.videoGameProgress()
            PastGameOutcome.Success(gameProgress.toSuccessPastGameScoringStateWithoutDetection())
        }

        return modifyOrNewPastGameContent(outcome, gameJourneyItem, existingMessage, ourPlayerAccountId)
    }

    context(scope: ComputationalScope)
    private suspend fun constructFailedMessageContent(
        gameJourneyItem: VideoGameJourneyItem,
        canDetectPersonhoodProgress: Boolean,
        existingMessage: ChatMessage?,
        ourPlayerAccountId: AccountId,
    ): ChatMessage.Content {
        val outcome = if (canDetectPersonhoodProgress) {
            val gameProgress = gamesProgressUseCase.awaitStateForFailedGame()
            PastGameOutcome.Failed(gameProgress.toFailedPastGameScoringState())
        } else {
            val gameProgress = gamesProgressUseCase.videoGameProgress()
            PastGameOutcome.Failed(gameProgress.toFailedPastGameScoringStateWithoutDetection())
        }

        return modifyOrNewPastGameContent(outcome, gameJourneyItem, existingMessage, ourPlayerAccountId)
    }

    context(scope: ComputationalScope)
    private suspend fun VideoGamesProgressUseCase.awaitStateForSuccessGame(): VideoGamesProgress {
        // Filter out impossible states for success game - if they appear it means cache was not updated yet
        return videoGamesProgressFlow().first { it !is VideoGamesProgress.FinalGameProcessing }
    }

    context(scope: ComputationalScope)
    private suspend fun VideoGamesProgressUseCase.awaitStateForFailedGame(): VideoGamesProgress {
        // Filter out impossible states for failed game - if they appear it means cache was not updated yet
        return videoGamesProgressFlow().first {
            it !is VideoGamesProgress.FinalGameProcessing &&
                it !is VideoGamesProgress.PersonhoodReached &&
                it !is VideoGamesProgress.ReadyToReachPersonhood
        }
    }

    private fun VideoGamesProgress.toSuccessPastGameScoringStateWithoutDetection(): SuccessPastGameScoring {
        return when (this) {
            VideoGamesProgress.ExternallyRecognized -> SuccessPastGameScoring.ExternallyRecognized
            else -> SuccessPastGameScoring.PersonhoodStateUnknown
        }
    }

    private fun VideoGamesProgress.toFailedPastGameScoringStateWithoutDetection(): FailedPastGameScoring {
        return when (this) {
            VideoGamesProgress.ExternallyRecognized -> FailedPastGameScoring.ExternallyRecognized
            else -> FailedPastGameScoring.PersonhoodStateUnknown
        }
    }

    private fun VideoGamesProgress.toSuccessPastGameScoringState(alreadyAnnouncedPersonhood: Boolean): SuccessPastGameScoring {
        return when (this) {
            VideoGamesProgress.ExternallyRecognized -> SuccessPastGameScoring.ExternallyRecognized

            is VideoGamesProgress.NotStarted -> SuccessPastGameScoring.Playing(score.gamesLeft, hasSuspendedPersonhood = false)

            is VideoGamesProgress.PersonhoodReached -> reachedPersonhoodScoring(alreadyAnnouncedPersonhood)

            is VideoGamesProgress.PlayingGames -> SuccessPastGameScoring.Playing(score.gamesLeft, hasSuspendedPersonhood)

            is VideoGamesProgress.ReadyToReachPersonhood -> reachedPersonhoodScoring(alreadyAnnouncedPersonhood)

            is VideoGamesProgress.FinalGameProcessing -> error("FinalGameProcessing state was filtered out, should not appear here")
        }
    }

    private fun reachedPersonhoodScoring(alreadyAnnouncedPersonhood: Boolean): SuccessPastGameScoring {
        return if (alreadyAnnouncedPersonhood) {
            SuccessPastGameScoring.AlreadyReachedPersonhood
        } else {
            SuccessPastGameScoring.ReachedPersonhood
        }
    }

    private fun VideoGamesProgress.toFailedPastGameScoringState(): FailedPastGameScoring {
        return when (this) {
            VideoGamesProgress.ExternallyRecognized -> FailedPastGameScoring.ExternallyRecognized

            is VideoGamesProgress.NotStarted -> FailedPastGameScoring.Playing(score.gamesLeft, hasSuspendedPersonhood = false)

            is VideoGamesProgress.PlayingGames -> FailedPastGameScoring.Playing(score.gamesLeft, hasSuspendedPersonhood)

            is VideoGamesProgress.ReadyToReachPersonhood -> error("ReadyToReachPersonhood state was filtered out, should not appear here")
            is VideoGamesProgress.PersonhoodReached -> error("PersonhoodReached state was filtered out, should not appear here")
            is VideoGamesProgress.FinalGameProcessing -> error("FinalGameProcessing state was filtered out, should not appear here")
        }
    }

    private suspend fun modifyOrNewPastGameContent(
        outcome: PastGameOutcome,
        gameJourneyItem: VideoGameJourneyItem,
        existingMessage: ChatMessage?,
        ourPlayerAccountId: AccountId,
    ): ChatMessage.Content {
        val customContent = if (existingMessage != null) {
            val existingContent = existingMessage.customContentOrNull<PastGameContent>()!!
            val avatarPaths = existingContent.playerAvatarPaths.ifEmpty {
                getPlayerAvatarPaths(gameJourneyItem.gameIndex, ourPlayerAccountId)
            }
            existingContent.copy(outcome = outcome, playerAvatarPaths = avatarPaths)
        } else {
            createNewPastGameContent(outcome, gameJourneyItem, ourPlayerAccountId)
        }

        return ChatMessage.Content.Custom(GameResultRenderer.ID, Result.success(customContent))
    }

    private suspend fun createNewPastGameContent(
        outcome: PastGameOutcome,
        gameJourneyItem: VideoGameJourneyItem,
        ourPlayerAccountId: AccountId
    ): PastGameContent {
        return PastGameContent(
            outcome = outcome,
            gameIndex = gameJourneyItem.gameIndex,
            timestamp = gameJourneyItem.timestamp?.toTimestamp() ?: System.currentTimeMillis(),
            playerAvatarPaths = getPlayerAvatarPaths(gameJourneyItem.gameIndex, ourPlayerAccountId)
        )
    }

    private suspend fun getPlayerAvatarPaths(
        gameIndex: GameIndex,
        ourPlayerAccountId: AccountId
    ): List<String> {
        return gamePlayersRepository.getGamePlayers(gameIndex)
            .filter { it != ourPlayerAccountId }
            .take(MAX_AVATAR_COUNT)
            .map { playerFrameFilePathCreator.getEncodedUri(gameIndex.value, it) }
    }

    private fun canDetectPersonhoodProgress(item: VideoGameJourneyItem, allItems: List<VideoGameJourneyItem>): Boolean {
        // We can only detect personhood progress if we are processing the last active game
        // For previous games the current VideoGamesProgress cannot be used to determine personhood progress at that point of time
        return item.gameIndex == allItems.lastNonFutureGame()?.gameIndex
    }
}
