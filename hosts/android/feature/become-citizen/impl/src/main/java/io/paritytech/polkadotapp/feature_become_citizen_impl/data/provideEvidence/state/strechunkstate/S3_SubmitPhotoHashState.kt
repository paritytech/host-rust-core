package io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate

import io.paritytech.polkadotapp.common.data.worker.stateMachine.WorkerStateMachineState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.SubmitEvidenceHashState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.UploadEvidenceState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.UploadEvidenceStateFactory
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.SubmitPhotoHashState.Params
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.upload.isFullAllocation

class SubmitPhotoHashState(
    private val stateFactory: UploadEvidenceStateFactory,
    override val params: Params,
) : SubmitEvidenceHashState(params.evidenceHash), WorkerStateMachineState.WithParams<Params> {
    data class Params(val evidenceHash: String)

    companion object {
        val ID = "SubmitPhotoHashState"
    }

    override val id = ID

    context(transition: UploadEvidenceState.Transition)
    override suspend fun nextState(): UploadEvidenceState {
        return if (transition.uploadSession.isFullAllocation()) {
            stateFactory.storeFirstVideoChunk()
        } else {
            stateFactory.extendAllocation()
        }
    }
}
