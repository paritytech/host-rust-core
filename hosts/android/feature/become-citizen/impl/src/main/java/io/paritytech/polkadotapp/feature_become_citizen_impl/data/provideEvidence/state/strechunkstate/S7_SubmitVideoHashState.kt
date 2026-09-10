package io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate

import io.paritytech.polkadotapp.common.data.worker.stateMachine.WorkerStateMachineState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.SubmitEvidenceHashState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.UploadEvidenceState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.UploadEvidenceStateFactory
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.SubmitVideoHashState.Params

class SubmitVideoHashState(
    private val stateFactory: UploadEvidenceStateFactory,
    override val params: Params
) : SubmitEvidenceHashState(params.evidenceHash), WorkerStateMachineState.WithParams<Params> {
    data class Params(val evidenceHash: String)

    companion object {
        val ID = "SubmitVideoHashState"
    }

    override val id = ID

    context(transition: UploadEvidenceState.Transition)
    override suspend fun nextState(): UploadEvidenceState {
        return stateFactory.awaitProvenCandidacy()
    }
}
