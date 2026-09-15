package io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate

import io.paritytech.polkadotapp.common.data.worker.stateMachine.error.TransitionDidNotSucceedException
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.notifications.EvidenceNotificationsPublisher
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.EvidenceUploadingNonTerminalState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.UploadEvidenceState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.UploadEvidenceStateFactory
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.upload.isCandidateProven

class AwaitProvenCandidacyState(
    private val stateFactory: UploadEvidenceStateFactory,
    private val evidenceNotificationsPublisher: EvidenceNotificationsPublisher
) : EvidenceUploadingNonTerminalState() {
    companion object {
        val ID = "AwaitProvenCandidacyState"
    }

    override val id = ID

    context(transition: UploadEvidenceState.Transition)
    override suspend fun performNonTerminalTransition(): Result<UploadEvidenceState> {
        // We immediately fail instead of waiting by subscription since approval of final case to become proven is long process
        // So we don't want to consume user resources and our quota - better to schedule retry
        if (!transition.uploadSession.isCandidateProven()) return Result.failure(TransitionDidNotSucceedException("Not yet proven"))

        evidenceNotificationsPublisher.publishVideoAccepted()

        return Result.success(stateFactory.registerPersonKey())
    }
}
