package io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail

import androidx.lifecycle.SavedStateHandle
import dagger.hilt.android.lifecycle.HiltViewModel
import io.novasama.substrate_sdk_android.extensions.fromHex
import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.TattooImage
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.TattooImageLoader
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.toTattooId
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.model.VoteCaseContext
import io.paritytech.polkadotapp.feature_mobrules_impl.domain.voting.MobruleInteractor
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.MobRulesRouter
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.model.CaseType
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.model.MediaEvidenceDetailUiState
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.model.MediaEvidenceThumbnail
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.model.VideoWatchingStatus
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.model.VotingOption
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.model.toMobRuleVote
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.player.ChunkedDataSourceFactory
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.math.BigInteger
import javax.inject.Inject

private const val REQUIRED_WATCH_SECONDS = 10
private const val COUNTDOWN_TICK_MILLIS = 1000L

@HiltViewModel
class MediaEvidenceDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val interactor: MobruleInteractor,
    private val router: MobRulesRouter,
    override val chunkedDataSourceFactory: ChunkedDataSourceFactory,
    private val tattooImageLoader: TattooImageLoader,
) : BaseViewModel(), MediaEvidenceDetailContract {
    private val payload: MediaEvidenceDetailPayload = savedStateHandle.getPayload()

    private val isVideoPlaying = MutableStateFlow(false)

    override val state = MutableStateFlow(
        MediaEvidenceDetailUiState(
            caseType = payload.caseType,
            caseId = payload.caseId,
            tattooImage = resolveTattooImage(),
            evidenceHashHex = payload.evidenceHashHex,
            viewOnly = payload.viewOnly,
            videoWatchingStatus = resolveInitialWatchingStatus(),
        )
    )

    init {
        if (state.value.videoWatchingStatus is VideoWatchingStatus.Countdown) {
            launchCountdownTimer()
        }
    }

    override fun onVoteClick(option: VotingOption) {
        launch {
            router.back()

            withContext(NonCancellable) {
                interactor.vote(
                    vote = option.toMobRuleVote(),
                    caseContext = buildVoteCaseContext()
                )
            }
        }
    }

    override fun onSelectThumbnail(thumbnail: MediaEvidenceThumbnail) {
        state.update { it.copy(selectedThumbnail = thumbnail) }
    }

    override fun onVideoPlayingChanged(isPlaying: Boolean) {
        this.isVideoPlaying.value = isPlaying
    }

    override fun onCloseClick() {
        router.back()
    }

    private fun resolveInitialWatchingStatus(): VideoWatchingStatus {
        if (payload.viewOnly) return VideoWatchingStatus.NotRequired
        if (payload.caseType != CaseType.VIDEO) return VideoWatchingStatus.NotRequired
        if (interactor.isVideoWatched(payload.caseId.toBigInteger())) return VideoWatchingStatus.Watched

        return VideoWatchingStatus.Countdown(REQUIRED_WATCH_SECONDS)
    }

    private fun launchCountdownTimer() {
        launch {
            isVideoPlaying.collectLatest { playing ->
                if (!playing) return@collectLatest

                while (true) {
                    delay(COUNTDOWN_TICK_MILLIS)

                    val current = state.value.videoWatchingStatus
                    if (current !is VideoWatchingStatus.Countdown) break

                    val remaining = current.secondsRemaining - 1
                    if (remaining <= 0) {
                        state.update { it.copy(videoWatchingStatus = VideoWatchingStatus.Watched) }
                        interactor.onReadyToVote(buildVoteCaseContext())
                        break
                    } else {
                        state.update { it.copy(videoWatchingStatus = VideoWatchingStatus.Countdown(remaining)) }
                    }
                }
            }
        }
    }

    private fun resolveTattooImage(): TattooImage {
        return tattooImageLoader.getTattooImage(
            payload.tattooId.toTattooId(),
            payload.tattooFamilyIdHex.fromHex()
        )
    }

    private fun buildVoteCaseContext(): VoteCaseContext {
        val caseId = BigInteger(payload.caseId)
        val evidenceHash = payload.evidenceHashHex.fromHex().toDataByteArray()
        val tattooId = payload.tattooId.toTattooId()
        val tattooFamilyId = payload.tattooFamilyIdHex.fromHex().toDataByteArray()

        return when (payload.caseType) {
            CaseType.PHOTO -> VoteCaseContext.Photo(
                caseId = caseId,
                evidenceHash = evidenceHash,
                tattooId = tattooId,
                tattooFamilyId = tattooFamilyId
            )

            CaseType.VIDEO -> VoteCaseContext.Video(
                caseId = caseId,
                evidenceHash = evidenceHash,
                tattooId = tattooId,
                tattooFamilyId = tattooFamilyId
            )
        }
    }
}
