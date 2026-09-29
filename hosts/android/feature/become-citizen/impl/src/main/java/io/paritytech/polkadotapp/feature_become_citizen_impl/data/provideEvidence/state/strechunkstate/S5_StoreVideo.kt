package io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate

import io.paritytech.polkadotapp.common.data.worker.stateMachine.WorkerStateMachineState
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.EvidenceType
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.model.ChunkIndex
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.model.RawEvidenceChunk
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.AwaitChunkConfirmationState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.StoreChunkState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.UploadEvidenceState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.UploadEvidenceStateFactory
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.storage.EvidenceStorage
import java.math.BigInteger

class StoreVideoChunkState(
    private val storage: EvidenceStorage,
    private val stateFactory: UploadEvidenceStateFactory,
    override val params: Params,
) : StoreChunkState(stateFactory, params.chunkIndex),
    WorkerStateMachineState.WithParams<StoreVideoChunkState.Params> {
    data class Params(val chunkIndex: ChunkIndex)

    companion object {
        val ID = "StoreVideo"
    }

    override val id = ID

    context(transition: UploadEvidenceState.Transition)
    override suspend fun getChunk(): Result<RawEvidenceChunk> {
        return storage.getRawEvidenceChunk(EvidenceType.VIDEO, params.chunkIndex.index, transition.uploadSession.chunkingConfig.chunkSize)
    }

    context(transition: UploadEvidenceState.Transition)
    override suspend fun nextState(
        authorizedTransactionsBeforeSubmission: BigInteger,
        uploadedChunk: RawEvidenceChunk
    ): UploadEvidenceState {
        val newParams = AwaitVideoChunkConfirmation.Params(authorizedTransactionsBeforeSubmission, params.chunkIndex)
        return stateFactory.awaitVideoChunkConfirmation(newParams)
    }
}

class AwaitVideoChunkConfirmation(
    private val stateFactory: UploadEvidenceStateFactory,
    override val params: Params
) : AwaitChunkConfirmationState(params.authorizedTransactionsBeforeSubmission, params.chunkIndex),
    WorkerStateMachineState.WithParams<AwaitVideoChunkConfirmation.Params> {
    data class Params(
        val authorizedTransactionsBeforeSubmission: BigInteger,
        val chunkIndex: ChunkIndex
    )

    companion object {
        val ID = "AwaitVideoChunkConfirmation"
    }

    override val id = ID

    context(transition: UploadEvidenceState.Transition)
    override suspend fun nextState(): UploadEvidenceState {
        return if (params.chunkIndex.isLast) {
            stateFactory.storeVideoMetadata()
        } else {
            val newParams = StoreVideoChunkState.Params(chunkIndex = params.chunkIndex.nextChunk())
            stateFactory.storeVideoChunk(newParams)
        }
    }
}
