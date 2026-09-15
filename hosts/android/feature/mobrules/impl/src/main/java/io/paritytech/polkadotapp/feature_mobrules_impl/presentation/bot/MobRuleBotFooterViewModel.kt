package io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot

import dagger.hilt.android.lifecycle.HiltViewModel
import io.novasama.substrate_sdk_android.extensions.toHexString
import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.common.utils.launchUnit
import io.paritytech.polkadotapp.common.utils.stateInBackground
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.toDomain
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.TattooImageLoader
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.toParcelable
import io.paritytech.polkadotapp.feature_chats_api.presentation.model.ChatFeedPayload
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.model.MobRuleCaseId
import io.paritytech.polkadotapp.feature_mobrules_impl.domain.voting.MobruleInteractor
import io.paritytech.polkadotapp.feature_mobrules_impl.domain.voting.VotingStateEvent
import io.paritytech.polkadotapp.feature_mobrules_impl.domain.voting.model.MobRuleCase
import io.paritytech.polkadotapp.feature_mobrules_impl.domain.voting.model.MobRuleCaseStatement
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.MobRulesRouter
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.model.CaseType
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.model.MobRuleBotFooterUiState
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.model.MobRuleVotedCaseContent
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.model.VotingCaseUiModel
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.model.toVoteCaseContext
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.MediaEvidenceDetailPayload
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.model.VotingOption
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.model.toMobRuleVote
import io.paritytech.polkadotapp.tools_ipfs_api.IpfsImageRequest
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject
import io.paritytech.polkadotapp.common.R as RCommon

@HiltViewModel
class MobRuleBotFooterViewModel @Inject constructor(
    private val interactor: MobruleInteractor,
    private val tattooImageLoader: TattooImageLoader,
    private val router: MobRulesRouter,
) : BaseViewModel(), MobRuleBotFooterContract {
    private val votedCaseIds = MutableStateFlow<Set<MobRuleCaseId>>(emptySet())

    override val votingFailedEvents = MutableSharedFlow<Int>()

    init {
        interactor.observeVotingState().onEach { event ->
            when (event) {
                is VotingStateEvent.ReadyToVote -> Unit
                is VotingStateEvent.Started -> votedCaseIds.update { it + event.caseContext.caseId }
                is VotingStateEvent.Failed -> {
                    votedCaseIds.update { it - event.caseContext.caseId }
                    votingFailedEvents.emit(RCommon.string.mob_rule_voting_error)
                }
                is VotingStateEvent.Completed -> Unit
            }
        }.launchIn(this)
    }

    override val state = interactor.observeCanUseMobruleAlias()
        .flatMapLatest { canUseAlias ->
            if (!canUseAlias) {
                flowOf(MobRuleBotFooterUiState.Suspended)
            } else {
                observeActiveState()
            }
        }
        .stateInBackground(initialValue = MobRuleBotFooterUiState.Active())

    override fun onVoteClick(case: VotingCaseUiModel, vote: VotingOption) {
        launch {
            val mobRuleVote = vote.toMobRuleVote()
            val caseContext = case.toVoteCaseContext()

            interactor.vote(
                vote = mobRuleVote,
                caseContext = caseContext
            )
        }
    }

    override fun openEvidenceDetail(case: VotingCaseUiModel) {
        launch {
            val evidenceHashHex = case.evidenceHashHex() ?: return@launch

            val payload = when (case) {
                is VotingCaseUiModel.Photo -> MediaEvidenceDetailPayload(
                    caseId = case.id.toString(),
                    caseType = CaseType.PHOTO,
                    evidenceHashHex = evidenceHashHex,
                    viewOnly = false,
                    tattooId = case.tattooId.toParcelable(),
                    tattooFamilyIdHex = case.tattooFamilyId.value.toHexString(withPrefix = false)
                )

                is VotingCaseUiModel.Video -> MediaEvidenceDetailPayload(
                    caseId = case.id.toString(),
                    caseType = CaseType.VIDEO,
                    evidenceHashHex = evidenceHashHex,
                    viewOnly = false,
                    tattooId = case.tattooId.toParcelable(),
                    tattooFamilyIdHex = case.tattooFamilyId.value.toHexString(withPrefix = false)
                )

                is VotingCaseUiModel.Credentials,
                is VotingCaseUiModel.UsernameValid -> return@launch
            }

            router.openEvidenceDetail(payload)
        }
    }

    override fun openVotedCaseDetail(content: MobRuleVotedCaseContent) {
        val hashHex = content.evidenceHashHex ?: return

        val payload = MediaEvidenceDetailPayload(
            caseId = content.caseId,
            caseType = content.caseType,
            evidenceHashHex = hashHex,
            viewOnly = true,
            tattooId = content.tattooId.toDomain().toParcelable(),
            tattooFamilyIdHex = content.tattooFamilyIdHex
        )

        router.openEvidenceDetail(payload)
    }

    override fun onReclaimPeerStatusClick() = launchUnit {
        val chatId = interactor.getActiveDimChatId()
        if (chatId == null) {
            Timber.e("No active DIM chat found for reclaim navigation")
            return@launchUnit
        }
        router.back()
        router.openChatFeed(ChatFeedPayload.existingChat(chatId))
    }

    private fun observeActiveState() = combine(
        interactor.observeCasesToVote(),
        votedCaseIds,
        interactor.observeWatchedVideoCaseIds()
    ) { result, votedIds, watchedVideoIds ->
        result.fold(
            onSuccess = { casesToVoteResult ->
                val proofOfInkCases = casesToVoteResult.cases
                    .filter { it.statement is MobRuleCaseStatement.ProofOfInk }
                    .filter { it.id !in votedIds }
                    .sortedBy { it.id }

                val hasEverVoted = casesToVoteResult.hasEverVotedOnChain || votedIds.isNotEmpty()
                val currentCase = proofOfInkCases.firstOrNull()
                val isVotingAllowed = currentCase == null || !currentCase.isVideoCase() || currentCase.id in watchedVideoIds

                MobRuleBotFooterUiState.Active(
                    currentCase = currentCase?.toUiModel(),
                    pendingCasesCount = (proofOfInkCases.size - 1).coerceAtLeast(0),
                    showAllCasesCompleted = proofOfInkCases.isEmpty() && hasEverVoted,
                    isVotingAllowed = isVotingAllowed
                )
            },
            onFailure = { MobRuleBotFooterUiState.Active() }
        )
    }

    private fun MobRuleCase.isVideoCase(): Boolean {
        return statement is MobRuleCaseStatement.ProofOfInk.Video
    }

    private fun VotingCaseUiModel.evidenceHashHex(): String? {
        return when (this) {
            is VotingCaseUiModel.Photo -> proofImage.contentHash.toHexString(withPrefix = false)
            is VotingCaseUiModel.Video -> evidenceHash.value.toHexString(withPrefix = false)
            is VotingCaseUiModel.Credentials,
            is VotingCaseUiModel.UsernameValid -> null
        }
    }

    private fun MobRuleCase.toUiModel(): VotingCaseUiModel {
        val proofOfInk = statement as MobRuleCaseStatement.ProofOfInk
        val tattooImage = tattooImageLoader.getTattooImage(proofOfInk.tattooId, proofOfInk.tattooFamilyId)
        val ipfsRequest = IpfsImageRequest(proofOfInk.evidenceHash)

        return when (proofOfInk) {
            is MobRuleCaseStatement.ProofOfInk.Photo -> VotingCaseUiModel.Photo(
                id = id,
                isSensitive = isSensitive,
                tattooImage = tattooImage,
                proofImage = ipfsRequest,
                tattooId = proofOfInk.tattooId,
                tattooFamilyId = proofOfInk.tattooFamilyId.toDataByteArray()
            )

            is MobRuleCaseStatement.ProofOfInk.Video -> VotingCaseUiModel.Video(
                id = id,
                isSensitive = isSensitive,
                tattooImage = tattooImage,
                evidenceHash = proofOfInk.evidenceHash.toDataByteArray(),
                proofVideo = ipfsRequest,
                tattooId = proofOfInk.tattooId,
                tattooFamilyId = proofOfInk.tattooFamilyId.toDataByteArray()
            )
        }
    }
}
