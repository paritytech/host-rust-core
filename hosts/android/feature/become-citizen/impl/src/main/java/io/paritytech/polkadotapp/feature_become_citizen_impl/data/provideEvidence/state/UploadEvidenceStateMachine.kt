package io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state

import io.paritytech.polkadotapp.common.data.worker.stateMachine.BaseWorkerStateMachine
import io.paritytech.polkadotapp.common.data.worker.stateMachine.WorkerStateMachine
import io.paritytech.polkadotapp.common.data.worker.stateMachine.WorkerStateMachineLocalSession
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.upload.EvidenceUploader
import javax.inject.Inject

typealias UploadEvidenceStateMachine = WorkerStateMachine<UploadEvidenceState>
typealias UploadEvidenceLocalSession = WorkerStateMachineLocalSession<UploadEvidenceState>

class UploadEvidenceStateMachineFactory @Inject constructor(
    private val stateFactory: UploadEvidenceStateFactory,
    private val localSession: UploadEvidenceLocalSession,
) {
    fun create(uploadSession: EvidenceUploader.UploadSession): UploadEvidenceStateMachine {
        return RealUploadEvidenceStateMachine(stateFactory, localSession, uploadSession)
    }
}

private class RealUploadEvidenceStateMachine(
    stateFactory: UploadEvidenceStateFactory,
    localSession: UploadEvidenceLocalSession,
    private val uploadSession: EvidenceUploader.UploadSession,
) : BaseWorkerStateMachine<UploadEvidenceState, UploadEvidenceState.Transition>(
    localSession = localSession,
    stateFactory = stateFactory
) {
    override suspend fun createTransition(): UploadEvidenceState.Transition {
        return Transition()
    }

    private inner class Transition : UploadEvidenceState.Transition {
        override val uploadSession: EvidenceUploader.UploadSession =
            this@RealUploadEvidenceStateMachine.uploadSession
    }
}
