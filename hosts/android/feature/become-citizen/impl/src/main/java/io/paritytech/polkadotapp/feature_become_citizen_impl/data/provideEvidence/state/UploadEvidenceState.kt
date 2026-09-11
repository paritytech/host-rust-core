package io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state

import io.paritytech.polkadotapp.common.data.worker.stateMachine.WorkerStateMachineState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.upload.EvidenceUploader.UploadSession

sealed interface UploadEvidenceState : WorkerStateMachineState<UploadEvidenceState, UploadEvidenceState.Transition> {
    interface Transition {
        val uploadSession: UploadSession
    }
}
