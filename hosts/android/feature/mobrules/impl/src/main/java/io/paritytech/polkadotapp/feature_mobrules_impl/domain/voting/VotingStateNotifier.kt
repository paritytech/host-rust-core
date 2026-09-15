package io.paritytech.polkadotapp.feature_mobrules_impl.domain.voting

import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.model.MobRuleCaseId
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.model.VoteCaseContext
import io.paritytech.polkadotapp.feature_mobrules_impl.domain.voting.model.MobRuleVote
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update
import javax.inject.Inject
import javax.inject.Singleton

sealed interface VotingStateEvent {
    val caseContext: VoteCaseContext

    data class ReadyToVote(override val caseContext: VoteCaseContext) : VotingStateEvent
    data class Started(val vote: MobRuleVote, override val caseContext: VoteCaseContext) : VotingStateEvent
    data class Completed(val vote: MobRuleVote, override val caseContext: VoteCaseContext) : VotingStateEvent
    data class Failed(override val caseContext: VoteCaseContext, val error: Throwable) : VotingStateEvent
}

interface VotingStateNotifier {
    suspend fun onReadyToVote(caseContext: VoteCaseContext)
    suspend fun onVoteStarted(vote: MobRuleVote, caseContext: VoteCaseContext)
    suspend fun onVoteCompleted(vote: MobRuleVote, caseContext: VoteCaseContext)
    suspend fun onVoteFailed(caseContext: VoteCaseContext, error: Throwable)
    fun observeState(): Flow<VotingStateEvent>
    fun isVideoWatched(caseId: MobRuleCaseId): Boolean
    fun observeWatchedVideoCaseIds(): Flow<Set<MobRuleCaseId>>
}

@Singleton
class RealVotingStateNotifier @Inject constructor() : VotingStateNotifier {
    private val events = MutableSharedFlow<VotingStateEvent>(extraBufferCapacity = 64)
    private val watchedVideoCaseIds = MutableStateFlow<Set<MobRuleCaseId>>(emptySet())

    override suspend fun onReadyToVote(caseContext: VoteCaseContext) {
        watchedVideoCaseIds.update { it + caseContext.caseId }
        events.emit(VotingStateEvent.ReadyToVote(caseContext))
    }

    override suspend fun onVoteStarted(vote: MobRuleVote, caseContext: VoteCaseContext) {
        events.emit(VotingStateEvent.Started(vote, caseContext))
    }

    override suspend fun onVoteCompleted(vote: MobRuleVote, caseContext: VoteCaseContext) {
        events.emit(VotingStateEvent.Completed(vote, caseContext))
    }

    override suspend fun onVoteFailed(caseContext: VoteCaseContext, error: Throwable) {
        events.emit(VotingStateEvent.Failed(caseContext, error))
    }

    override fun observeState(): Flow<VotingStateEvent> = events

    override fun isVideoWatched(caseId: MobRuleCaseId): Boolean = caseId in watchedVideoCaseIds.value

    override fun observeWatchedVideoCaseIds(): Flow<Set<MobRuleCaseId>> = watchedVideoCaseIds
}
