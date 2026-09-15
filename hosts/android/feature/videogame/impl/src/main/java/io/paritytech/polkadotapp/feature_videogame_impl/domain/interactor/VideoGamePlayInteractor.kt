package io.paritytech.polkadotapp.feature_videogame_impl.domain.interactor

import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_videogame_impl.data.VideoGameInfoSyncService
import io.paritytech.polkadotapp.feature_videogame_impl.data.getCurrentActiveGameInfo
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.webrtc.GestureAcceptanceMessage
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.VideoGameRepositoryInternal
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.VideoGameTooltipsRepository
import io.paritytech.polkadotapp.feature_videogame_impl.domain.BannedPlayersRepository
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGameProcessState
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGameVote
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.Vote
import io.paritytech.polkadotapp.feature_videogame_impl.domain.timeline.VideoGameTimelineService
import io.paritytech.polkadotapp.feature_videogame_impl.domain.timeline.currentActiveGameTimeline
import io.paritytech.polkadotapp.feature_videogame_impl.domain.usecase.PlayingAccountUseCase
import io.paritytech.polkadotapp.feature_videogame_impl.service.GestureAcceptanceChannel
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject
import kotlin.time.Duration

interface VideoGamePlayInteractor {
    context(scope: ComputationalScope)
    fun subscribeGameTimeline(): Flow<Duration>

    context(scope: ComputationalScope)
    suspend fun trySaveVotes(
        round: VideoGameProcessState.Round,
        connectedPlayers: Set<AccountId>,
        votes: Set<AccountId>
    )

    fun shouldShowShowGestureTooltip(): Boolean

    fun shouldShowCopyGestureTooltip(): Boolean

    fun setShowGesturesTooltipShown()

    fun setCopyGesturesTooltipShown()

    fun observeBannedPlayers(): Flow<Set<AccountId>>

    suspend fun banPlayer(accountId: AccountId)

    suspend fun unbanPlayer(accountId: AccountId)

    fun subscribeIncomingAcceptances(): Flow<GestureAcceptanceMessage>

    suspend fun sendAcceptanceToPlayer(targetAccountId: AccountId, message: GestureAcceptanceMessage)
}

class RealVideoGamePlayInteractor @Inject constructor(
    private val playingAccountUseCase: PlayingAccountUseCase,
    private val timelineService: VideoGameTimelineService,
    private val gameInfoSyncService: VideoGameInfoSyncService,
    private val videoGameRepository: VideoGameRepositoryInternal,
    private val videoGameTooltipsRepository: VideoGameTooltipsRepository,
    private val recordGamePlayersUseCase: RecordGamePlayersUseCase,
    private val bannedPlayersRepository: BannedPlayersRepository,
    private val gestureAcceptanceChannel: GestureAcceptanceChannel
) : VideoGamePlayInteractor {
    context(scope: ComputationalScope)
    override fun subscribeGameTimeline(): Flow<Duration> {
        return timelineService.currentActiveGameTimeline()
    }

    context(scope: ComputationalScope)
    override suspend fun trySaveVotes(
        round: VideoGameProcessState.Round,
        connectedPlayers: Set<AccountId>,
        votes: Set<AccountId>
    ) {
        if (!connectedPlayers.contains(round.currentHost)) return

        val currentPlayerAccount = playingAccountUseCase.getOurPlayerAccountId()
        val gameIndex = gameInfoSyncService.getCurrentActiveGameInfo().index
        val roundIndex = round.roundIndex

        val votesToSave = round.roundPlayers.mapIndexedNotNull { index, playerAccount ->
            if (playerAccount == currentPlayerAccount) return@mapIndexedNotNull null
            if (playerAccount == round.currentHost) return@mapIndexedNotNull null

            val vote = when {
                votes.contains(playerAccount) -> Vote.Person
                connectedPlayers.contains(playerAccount) -> Vote.NonPerson
                else -> Vote.NotParticipated
            }

            VideoGameVote(
                vote = vote,
                playerIndex = index,
                gameIndex = gameIndex,
                roundIndex = roundIndex,
                accountId = playerAccount
            )
        }

        videoGameRepository.saveVotes(votesToSave)
    }

    override fun shouldShowShowGestureTooltip(): Boolean {
        return !videoGameTooltipsRepository.isShowGesturesTooltipShown()
    }

    override fun shouldShowCopyGestureTooltip(): Boolean {
        return !videoGameTooltipsRepository.isCopyGestureTooltipShown()
    }

    override fun setShowGesturesTooltipShown() {
        videoGameTooltipsRepository.setShowGestureTooltipShown()
    }

    override fun setCopyGesturesTooltipShown() {
        videoGameTooltipsRepository.setCopyGestureTooltipShown()
    }
    override fun observeBannedPlayers() = bannedPlayersRepository.subscribeBannedPlayers()

    override suspend fun banPlayer(accountId: AccountId) = bannedPlayersRepository.ban(accountId)

    override suspend fun unbanPlayer(accountId: AccountId) = bannedPlayersRepository.unban(accountId)

    override fun subscribeIncomingAcceptances(): Flow<GestureAcceptanceMessage> =
        gestureAcceptanceChannel.subscribeIncomingAcceptances()

    override suspend fun sendAcceptanceToPlayer(targetAccountId: AccountId, message: GestureAcceptanceMessage) =
        gestureAcceptanceChannel.sendAcceptanceToPlayer(targetAccountId, message)
}
