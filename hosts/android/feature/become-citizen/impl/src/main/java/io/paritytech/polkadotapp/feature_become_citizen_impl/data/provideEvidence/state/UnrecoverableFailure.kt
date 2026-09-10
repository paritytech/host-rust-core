package io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state

import io.paritytech.polkadotapp.common.data.worker.stateMachine.WorkerStateMachineState
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.EvidenceUploadingFailureReason
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.UnrecoverableFailure.Params

class UnrecoverableFailure(
    val retryState: UploadEvidenceState,
    override val params: Params
) : EvidenceUploadingTerminalState(), WorkerStateMachineState.WithParams<Params> {
    data class Params(val reason: EvidenceUploadingFailureReason)

    companion object {
        val ID = "UnrecoverableFailure"
    }

    override val id = ID
}
