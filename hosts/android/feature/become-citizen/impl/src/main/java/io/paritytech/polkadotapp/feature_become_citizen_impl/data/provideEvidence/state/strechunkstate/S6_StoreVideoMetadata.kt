package io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate

import com.google.gson.Gson
import io.paritytech.polkadotapp.common.data.worker.stateMachine.WorkerStateMachineState
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.EvidenceType
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.model.ChunkIndex
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.AwaitChunkConfirmationState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.StoreEvidenceMetadataState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.UploadEvidenceState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.UploadEvidenceStateFactory
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.storage.EvidenceStorage
import java.math.BigInteger

class StoreVideoMetadataState(
    private val storage: EvidenceStorage,
    private val stateFactory: UploadEvidenceStateFactory,
    private val gson: Gson,
) : StoreEvidenceMetadataState(storage, stateFactory, gson) {
    companion object {
        val ID = "StoreVideoMetadataState"
    }

    override val id = ID

    override val evidenceType: EvidenceType = EvidenceType.VIDEO

    context(transition: UploadEvidenceState.Transition)
    override suspend fun nextState(
        authorizedTransactionsBeforeSubmission: BigInteger,
        evidenceHash: String
    ): UploadEvidenceState {
        val newParams = AwaitVideoMetadataConfirmationState.Params(evidenceHash, authorizedTransactionsBeforeSubmission)
        return stateFactory.awaitVideoMetadataConfirmation(newParams)
    }
}

class AwaitVideoMetadataConfirmationState(
    private val stateFactory: UploadEvidenceStateFactory,
    override val params: Params
) : AwaitChunkConfirmationState(params.authorizedTransactionsBeforeSubmission, ChunkIndex.singleChunk()),
    WorkerStateMachineState.WithParams<AwaitVideoMetadataConfirmationState.Params> {
    data class Params(val evidenceHash: String, val authorizedTransactionsBeforeSubmission: BigInteger)

    companion object {
        val ID = "AwaitVideoMetadataConfirmationState"
    }

    override val id = ID

    context(transition: UploadEvidenceState.Transition)
    override suspend fun nextState(): UploadEvidenceState {
        val newParams = SubmitVideoHashState.Params(params.evidenceHash)
        return stateFactory.submitVideoHash(newParams)
    }
}
