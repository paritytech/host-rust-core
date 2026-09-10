package io.paritytech.polkadotapp.feature_mobrules_impl.domain.voting

import io.novasama.substrate_sdk_android.hash.isPositive
import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchContext
import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.utils.coerceToUnit
import io.paritytech.polkadotapp.common.utils.flatMap
import io.paritytech.polkadotapp.common.utils.getOrEmpty
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_become_citizen_api.data.repository.TattooRepository
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooFamily
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooFamilyIndex
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatId
import io.paritytech.polkadotapp.feature_identity_api.domain.models.IdentityCredentialPlatform
import io.paritytech.polkadotapp.feature_mobrules_impl.data.MOB_RULE
import io.paritytech.polkadotapp.feature_mobrules_impl.data.signer.origin.VotingOrigins
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.MobRuleCasesRepository
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.mobRule
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.model.MobRuleCaseId
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.model.MobRuleOpenCase
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.model.VoteCaseContext
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.model.VoteCaseStatement
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.vote
import io.paritytech.polkadotapp.feature_mobrules_impl.domain.voting.model.CasesToVoteResult
import io.paritytech.polkadotapp.feature_mobrules_impl.domain.voting.model.MobRuleCase
import io.paritytech.polkadotapp.feature_mobrules_impl.domain.voting.model.MobRuleCaseStatement
import io.paritytech.polkadotapp.feature_mobrules_impl.domain.voting.model.MobRuleVote
import io.paritytech.polkadotapp.feature_people_api.domain.dim.DimCommitmentHandler
import io.paritytech.polkadotapp.feature_people_api.domain.dim.DimState
import io.paritytech.polkadotapp.feature_people_api.domain.useCase.PersonStatusUseCase
import io.paritytech.polkadotapp.feature_transactions.api.data.ExtrinsicService
import io.paritytech.polkadotapp.feature_transactions.api.data.flattenExecutionFailure
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject

interface MobruleInteractor {
    fun observeCasesToVote(): Flow<Result<CasesToVoteResult>>

    fun observeVotingState(): Flow<VotingStateEvent>

    fun observeWatchedVideoCaseIds(): Flow<Set<MobRuleCaseId>>

    fun isVideoWatched(caseId: MobRuleCaseId): Boolean

    suspend fun onReadyToVote(caseContext: VoteCaseContext)

    suspend fun vote(
        vote: MobRuleVote,
        caseContext: VoteCaseContext
    ): Result<Unit>

    fun observeCanUseMobruleAlias(): Flow<Boolean>

    context(scope: ComputationalScope)
    suspend fun getActiveDimChatId(): ChatId?
}

class RealMobruleInteractor @Inject constructor(
    private val mobRuleCasesRepository: MobRuleCasesRepository,
    private val chainRegistry: ChainRegistry,
    private val extrinsicService: ExtrinsicService,
    private val accountRepository: AccountRepository,
    private val tattooRepository: TattooRepository,
    private val votingOrigins: VotingOrigins,
    private val votingStateNotifier: VotingStateNotifier,
    private val personStatusUseCase: PersonStatusUseCase,
    private val dimCommitmentHandlers: Set<@JvmSuppressWildcards DimCommitmentHandler>,
) : MobruleInteractor {
    override fun observeVotingState(): Flow<VotingStateEvent> =
        votingStateNotifier.observeState()

    override fun observeWatchedVideoCaseIds(): Flow<Set<MobRuleCaseId>> =
        votingStateNotifier.observeWatchedVideoCaseIds()

    override fun isVideoWatched(caseId: MobRuleCaseId): Boolean =
        votingStateNotifier.isVideoWatched(caseId)

    override fun observeCanUseMobruleAlias(): Flow<Boolean> =
        personStatusUseCase.canUseAliasFlow(BandersnatchContext.MOB_RULE)

    context(scope: ComputationalScope)
    override suspend fun getActiveDimChatId(): ChatId? {
        return dimCommitmentHandlers.firstNotNullOfOrNull { handler ->
            val state = handler.observeState().first()
            ChatId.fromChatBotId(handler.botId).takeIf { state is DimState.Started }
        }
    }

    override suspend fun onReadyToVote(caseContext: VoteCaseContext) {
        votingStateNotifier.onReadyToVote(caseContext)
    }

    override fun observeCasesToVote(): Flow<Result<CasesToVoteResult>> {
        return flow {
            val chainId = chainRegistry.knownChains.people

            val initialUserVotes = fetchCurrentUserVotes(chainId).getOrEmpty()

            val families = tattooRepository.getAllDesignFamilies(chainId)
                .getOrElse {
                    emit(Result.failure(it))
                    return@flow
                }

            val familiesMap = families.associateBy { it.kind.familyIndex }

            emitAll(
                mobRuleCasesRepository.casesCountFlow(chainId).map {
                    mobRuleCasesRepository.openCases(chainId).map { cases ->
                        val filteredCases = cases.mapNotNull { (caseId, case) ->
                            if (caseId in initialUserVotes) return@mapNotNull null

                            case.toActiveCase(caseId, familiesMap)
                        }

                        CasesToVoteResult(
                            cases = filteredCases,
                            hasEverVotedOnChain = initialUserVotes.isNotEmpty()
                        )
                    }
                }
            )
        }
    }

    override suspend fun vote(
        vote: MobRuleVote,
        caseContext: VoteCaseContext
    ): Result<Unit> {
        votingStateNotifier.onVoteStarted(vote, caseContext)

        val chain = chainRegistry.peopleChain()

        val result = votingOrigins.mobRuleOrigin().flatMap { transactionOrigin ->
            extrinsicService.submitExtrinsicAndAwaitExecution(
                chain = chain,
                origin = transactionOrigin
            ) {
                mobRule.vote(caseContext.caseId, vote)
            }
                .flattenExecutionFailure()
                .coerceToUnit()
        }

        result
            .onSuccess { votingStateNotifier.onVoteCompleted(vote, caseContext) }
            .onFailure { votingStateNotifier.onVoteFailed(caseContext, it) }

        return result
    }

    private suspend fun fetchCurrentUserVotes(chainId: ChainId): Result<Set<MobRuleCaseId>> {
        val mobRuleAlias = accountRepository.getCandidateAlias(BandersnatchContext.MOB_RULE)
        return mobRuleCasesRepository.getVotedCases(chainId, mobRuleAlias).map { it.toSet() }
    }

    private fun MobRuleOpenCase.toActiveCase(selfCaseId: MobRuleCaseId, tattooFamilies: Map<TattooFamilyIndex, TattooFamily>): MobRuleCase? {
        return MobRuleCase(
            id = selfCaseId,
            isSensitive = tally.contempt.isPositive(),
            statement = details.statement.toDomain(tattooFamilies) ?: return null
        )
    }

    private fun VoteCaseStatement.toDomain(tattooFamilies: Map<TattooFamilyIndex, TattooFamily>): MobRuleCaseStatement? {
        return when (this) {
            is VoteCaseStatement.ProofOfInk -> toDomain(tattooFamilies)
            is VoteCaseStatement.IdentityCredential -> toDomain()
            is VoteCaseStatement.UsernameValid -> toDomain()
            is VoteCaseStatement.Unknown -> null
        }
    }

    private fun VoteCaseStatement.ProofOfInk.toDomain(tattooFamilies: Map<TattooFamilyIndex, TattooFamily>): MobRuleCaseStatement.ProofOfInk {
        return if (probableAcceptable) {
            MobRuleCaseStatement.ProofOfInk.Photo(
                tattooId = tattooId,
                tattooFamilyId = tattooFamilies.getValue(tattooId.familyIndex).id,
                evidenceHash = evidence
            )
        } else {
            MobRuleCaseStatement.ProofOfInk.Video(
                tattooId = tattooId,
                tattooFamilyId = tattooFamilies.getValue(tattooId.familyIndex).id,
                evidenceHash = evidence
            )
        }
    }

    private fun VoteCaseStatement.IdentityCredential.toDomain(): MobRuleCaseStatement.IdentityCredential? {
        return MobRuleCaseStatement.IdentityCredential(
            platform = IdentityCredentialPlatform.fromValue(platform.platformName, platform.username) ?: return null,
            userPlatformTag = platform.username,
            evidence = evidence
        )
    }

    private fun VoteCaseStatement.UsernameValid.toDomain(): MobRuleCaseStatement.UsernameValid {
        return MobRuleCaseStatement.UsernameValid(username = username)
    }
}
