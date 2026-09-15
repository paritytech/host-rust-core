package io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state

import com.google.gson.Gson
import io.novasama.substrate_sdk_android.extensions.fromHex
import io.novasama.substrate_sdk_android.extensions.toHexString
import io.novasama.substrate_sdk_android.hash.Hasher.blake2b256
import io.paritytech.polkadotapp.common.data.worker.stateMachine.NonTerminalState
import io.paritytech.polkadotapp.common.data.worker.stateMachine.TerminalState
import io.paritytech.polkadotapp.common.utils.InformationSize.Companion.bytes
import io.paritytech.polkadotapp.common.utils.chunked
import io.paritytech.polkadotapp.common.utils.flatMap
import io.paritytech.polkadotapp.feature_become_citizen_api.data.model.EvidenceMetadata
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.EvidenceType
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.EvidenceUploadingFailureReason
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.model.ChunkIndex
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.model.RawEvidenceChunk
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.storage.EvidenceStorage
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.upload.getCurrentBulletInBlockNumber
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.upload.getCurrentStorageAuthorization
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.upload.requireCurrentStorageAuthorization
import io.paritytech.polkadotapp.feature_transaction_storage_api.domain.model.hasCapacityFor
import io.paritytech.polkadotapp.feature_transaction_storage_api.domain.model.hasExpiredAt
import io.paritytech.polkadotapp.feature_transaction_storage_api.domain.model.storedTransactionAfter
import kotlinx.coroutines.flow.first
import timber.log.Timber
import java.math.BigInteger

abstract class EvidenceUploadingTerminalState :
    UploadEvidenceState,
    TerminalState<UploadEvidenceState, UploadEvidenceState.Transition>()

abstract class EvidenceUploadingNonTerminalState :
    UploadEvidenceState,
    NonTerminalState<UploadEvidenceState, UploadEvidenceState.Transition>()

abstract class StoreChunkState(
    private val stateFactory: UploadEvidenceStateFactory,
    val chunkIndex: ChunkIndex,
) : EvidenceUploadingNonTerminalState() {
    context(transition: UploadEvidenceState.Transition)
    abstract suspend fun getChunk(): Result<RawEvidenceChunk>

    context(transition: UploadEvidenceState.Transition)
    abstract suspend fun nextState(
        authorizedTransactionsBeforeSubmission: BigInteger,
        uploadedChunk: RawEvidenceChunk,
    ): UploadEvidenceState

    context(transition: UploadEvidenceState.Transition)
    override suspend fun performNonTerminalTransition(): Result<UploadEvidenceState> {
        return getChunk().flatMap { chunk ->
            val unrecoverableFailureReason = validateCanUploadChunk(chunk)
            if (unrecoverableFailureReason != null) {
                val failureParams = UnrecoverableFailure.Params(unrecoverableFailureReason)
                return@flatMap Result.success(stateFactory.unrecoverableFailureFromCurrent(failureParams))
            }

            val authorizedTransactionsBeforeSubmission = transition.uploadSession.requireCurrentStorageAuthorization().extent.transactionsAllowance

            Timber.d("Storing chunk of size ${chunk.value.size} bytes")

            transition.uploadSession.storeEvidence(chunk).map {
                nextState(authorizedTransactionsBeforeSubmission, chunk)
            }
        }
    }

    context(transition: UploadEvidenceState.Transition)
    private suspend fun validateCanUploadChunk(
        chunk: RawEvidenceChunk
    ): EvidenceUploadingFailureReason? {
        val storageAuthorization = transition.uploadSession.getCurrentStorageAuthorization()
        val blockNumber = transition.uploadSession.getCurrentBulletInBlockNumber()

        return when {
            storageAuthorization == null -> EvidenceUploadingFailureReason.NO_STORAGE_AUTHORIZATION
            storageAuthorization.hasExpiredAt(blockNumber) -> EvidenceUploadingFailureReason.STORAGE_EXPIRED
            !storageAuthorization.hasCapacityFor(chunk.value.size.bytes) -> {
                Timber.e("Storage capacity exceeded! Chunk size: ${chunk.value.size} bytes, total file size: ${chunk.totalSize} bytes)")
                EvidenceUploadingFailureReason.STORAGE_CAPACITY_EXCEEDED
            }
            else -> null
        }
    }
}

abstract class AwaitChunkConfirmationState(
    private val authorizedTransactionsBeforeSubmission: BigInteger,
    val chunkIndex: ChunkIndex,
) : EvidenceUploadingNonTerminalState() {
    context(transition: UploadEvidenceState.Transition)
    abstract suspend fun nextState(): UploadEvidenceState

    context(transition: UploadEvidenceState.Transition)
    override suspend fun performNonTerminalTransition(): Result<UploadEvidenceState> {
        return runCatching {
            awaitTransactionStored()

            nextState()
        }
    }

    context(transition: UploadEvidenceState.Transition)
    private suspend fun awaitTransactionStored() {
        transition.uploadSession.subscriptions.await().bulletIn.authorization.first {
            it != null && it.storedTransactionAfter(authorizedTransactionsBeforeSubmission)
        }
    }
}

abstract class StoreEvidenceMetadataState(
    private val storage: EvidenceStorage,
    private val stateFactory: UploadEvidenceStateFactory,
    private val gson: Gson,
) : StoreChunkState(stateFactory, chunkIndex = ChunkIndex.singleChunk()) {
    abstract val evidenceType: EvidenceType

    context(transition: UploadEvidenceState.Transition)
    protected abstract suspend fun nextState(
        authorizedTransactionsBeforeSubmission: BigInteger,
        evidenceHash: String
    ): UploadEvidenceState

    context(transition: UploadEvidenceState.Transition)
    final override suspend fun getChunk(): Result<RawEvidenceChunk> {
        return storage.generateEvidenceMetadata(evidenceType).map { evidenceMetadata ->
            val chunkValue = gson.toJson(evidenceMetadata)

            Timber.d("Constructed evidence metadata file: $chunkValue")

            RawEvidenceChunk(
                value = chunkValue.encodeToByteArray(),
                isLast = true,
                totalSize = evidenceMetadata.totalSize
            )
        }
    }

    context(transition: UploadEvidenceState.Transition)
    final override suspend fun nextState(
        authorizedTransactionsBeforeSubmission: BigInteger,
        uploadedChunk: RawEvidenceChunk
    ): UploadEvidenceState {
        return nextState(authorizedTransactionsBeforeSubmission, uploadedChunk.value.calculateHash())
    }

    context(transition: UploadEvidenceState.Transition)
    private suspend fun EvidenceStorage.generateEvidenceMetadata(type: EvidenceType): Result<EvidenceMetadata> {
        return getRawEvidence(type).map { wholeEvidence ->
            val rootHash = wholeEvidence.value.calculateHash()

            val chunkSize = transition.uploadSession.chunkingConfig.chunkSize.inWholeBytes.toInt()
            val chunkHashes = wholeEvidence.value.chunked(chunkSize).map { it.calculateHash() }

            val fileName = storage.getFileName(type)

            EvidenceMetadata(
                chunks = chunkHashes,
                hash = rootHash,
                totalSize = wholeEvidence.value.size.toLong(),
                path = fileName
            )
        }
    }

    private fun ByteArray.calculateHash(): String = blake2b256().toHexString(true)
}

abstract class SubmitEvidenceHashState(
    private val evidenceHash: String,
) : EvidenceUploadingNonTerminalState() {
    context(transition: UploadEvidenceState.Transition)
    abstract suspend fun nextState(): UploadEvidenceState

    context(transition: UploadEvidenceState.Transition)
    override suspend fun performNonTerminalTransition(): Result<UploadEvidenceState> {
        return transition.uploadSession.submitEvidenceHash(evidenceHash.fromHex()).map {
            nextState()
        }
    }
}
