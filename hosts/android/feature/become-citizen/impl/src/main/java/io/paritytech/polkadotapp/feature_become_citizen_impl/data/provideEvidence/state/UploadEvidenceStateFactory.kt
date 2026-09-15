package io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state

import com.google.gson.Gson
import io.paritytech.polkadotapp.common.data.worker.stateMachine.WorkerStateFactory
import io.paritytech.polkadotapp.common.data.worker.stateMachine.WorkerStateStore
import io.paritytech.polkadotapp.common.data.worker.stateMachine.getParams
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.BandersnatchSecretsStorage
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.EvidenceType
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.notifications.EvidenceNotificationsPublisher
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.AllDone
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.AwaitExtendAllocationConfirmationState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.AwaitPhotoChunkConfirmation
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.AwaitPhotoMetadataConfirmationState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.AwaitProvenCandidacyState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.AwaitStorageAuthorizationState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.AwaitVideoChunkConfirmation
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.AwaitVideoMetadataConfirmationState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.ExtendAllocationState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.RegisterPersonKeyState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.StartPersonSetupState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.StorePhotoChunkState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.StorePhotoMetadataState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.StoreVideoChunkState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.StoreVideoMetadataState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.SubmitPhotoHashState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.SubmitVideoHashState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.storage.EvidenceStorage
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.storage.getFirstChunkIndex
import io.paritytech.polkadotapp.feature_people_api.data.personSetup.PersonSetupStarter
import io.paritytech.polkadotapp.feature_vouchers_api.data.VoucherRepository
import javax.inject.Inject

class UploadEvidenceStateFactory @Inject constructor(
    private val storage: EvidenceStorage,
    private val gson: Gson,
    private val bandersnatchSecretsStorage: BandersnatchSecretsStorage,
    private val voucherRepository: VoucherRepository,
    private val personSetupStarter: PersonSetupStarter,
    private val evidenceNotificationsPublisher: EvidenceNotificationsPublisher
) : WorkerStateFactory<UploadEvidenceState> {
    override fun createState(
        stateId: String,
        store: WorkerStateStore<UploadEvidenceState>
    ): UploadEvidenceState? {
        return when (stateId) {
            AwaitStorageAuthorizationState.ID -> awaitStorageAuthorization()

            StorePhotoChunkState.ID -> storePhotoChunk(store.getParams())
            AwaitPhotoChunkConfirmation.ID -> awaitPhotoChunkConfirmation(store.getParams())
            StorePhotoMetadataState.ID -> storePhotoMetadata()
            AwaitPhotoMetadataConfirmationState.ID -> awaitPhotoMetadataConfirmation(
                store.getParams()
            )

            SubmitPhotoHashState.ID -> submitPhotoHash(store.getParams())

            ExtendAllocationState.ID -> extendAllocation()
            AwaitExtendAllocationConfirmationState.ID -> awaitExtendAllocationConfirmation(store.getParams())

            StoreVideoChunkState.ID -> storeVideoChunk(store.getParams())

            AwaitVideoChunkConfirmation.ID -> awaitVideoChunkConfirmation(store.getParams())

            StoreVideoMetadataState.ID -> storeVideoMetadata()
            AwaitVideoMetadataConfirmationState.ID -> awaitVideoMetadataConfirmation(
                store.getParams()
            )

            SubmitVideoHashState.ID -> submitVideoHash(store.getParams())

            AllDone.ID -> allDone()

            AwaitProvenCandidacyState.ID -> awaitProvenCandidacy()

            RegisterPersonKeyState.ID -> registerPersonKey()

            StartPersonSetupState.ID -> startPersonSetup()

            UnrecoverableFailure.ID -> {
                val failedState = store.getRetryState()

                unrecoverableFailure(store.getParams(), failedState)
            }

            else -> null
        }
    }

    override fun createDefaultState(): UploadEvidenceState {
        return awaitStorageAuthorization()
    }

    fun awaitStorageAuthorization(): AwaitStorageAuthorizationState {
        return AwaitStorageAuthorizationState(stateFactory = this)
    }

    fun storePhotoChunk(params: StorePhotoChunkState.Params): StorePhotoChunkState {
        return StorePhotoChunkState(storage, stateFactory = this, params)
    }

    context(transition: UploadEvidenceState.Transition)
    suspend fun storeFirstPhotoChunk(): StorePhotoChunkState {
        val firstChunkIndex = storage.getFirstChunkIndex(EvidenceType.PHOTO, transition.uploadSession.chunkingConfig.chunkSize)
        val params = StorePhotoChunkState.Params(firstChunkIndex)

        return StorePhotoChunkState(storage, stateFactory = this, params = params)
    }

    fun awaitPhotoChunkConfirmation(
        params: AwaitPhotoChunkConfirmation.Params
    ): AwaitPhotoChunkConfirmation {
        return AwaitPhotoChunkConfirmation(stateFactory = this, params)
    }

    fun storePhotoMetadata(): StorePhotoMetadataState {
        return StorePhotoMetadataState(this, storage, gson)
    }

    fun awaitPhotoMetadataConfirmation(
        params: AwaitPhotoMetadataConfirmationState.Params
    ): AwaitPhotoMetadataConfirmationState {
        return AwaitPhotoMetadataConfirmationState(stateFactory = this, params)
    }

    fun submitPhotoHash(params: SubmitPhotoHashState.Params): SubmitPhotoHashState {
        return SubmitPhotoHashState(stateFactory = this, params)
    }

    fun extendAllocation(): ExtendAllocationState {
        return ExtendAllocationState(stateFactory = this)
    }

    fun awaitExtendAllocationConfirmation(params: AwaitExtendAllocationConfirmationState.Params): AwaitExtendAllocationConfirmationState {
        return AwaitExtendAllocationConfirmationState(
            stateFactory = this,
            evidenceNotificationsPublisher = evidenceNotificationsPublisher,
            params = params
        )
    }

    fun storeVideoChunk(params: StoreVideoChunkState.Params): StoreVideoChunkState {
        return StoreVideoChunkState(storage, stateFactory = this, params)
    }

    context(transition: UploadEvidenceState.Transition)
    suspend fun storeFirstVideoChunk(): StoreVideoChunkState {
        val firstChunkIndex = storage.getFirstChunkIndex(EvidenceType.VIDEO, transition.uploadSession.chunkingConfig.chunkSize)
        val params = StoreVideoChunkState.Params(firstChunkIndex)

        return StoreVideoChunkState(storage, stateFactory = this, params = params)
    }

    fun awaitVideoChunkConfirmation(params: AwaitVideoChunkConfirmation.Params): AwaitVideoChunkConfirmation {
        return AwaitVideoChunkConfirmation(stateFactory = this, params)
    }

    fun storeVideoMetadata(): StoreVideoMetadataState {
        return StoreVideoMetadataState(storage, this, gson)
    }

    fun awaitVideoMetadataConfirmation(
        params: AwaitVideoMetadataConfirmationState.Params
    ): AwaitVideoMetadataConfirmationState {
        return AwaitVideoMetadataConfirmationState(stateFactory = this, params)
    }

    fun submitVideoHash(params: SubmitVideoHashState.Params): SubmitVideoHashState {
        return SubmitVideoHashState(stateFactory = this, params)
    }

    fun awaitProvenCandidacy(): AwaitProvenCandidacyState {
        return AwaitProvenCandidacyState(
            stateFactory = this,
            evidenceNotificationsPublisher = evidenceNotificationsPublisher
        )
    }

    fun registerPersonKey(): RegisterPersonKeyState {
        return RegisterPersonKeyState(bandersnatchSecretsStorage, stateFactory = this)
    }

    fun startPersonSetup(): StartPersonSetupState {
        return StartPersonSetupState(personSetupStarter, stateFactory = this)
    }

    fun allDone(): AllDone {
        return AllDone()
    }

    fun unrecoverableFailure(params: UnrecoverableFailure.Params, retryState: UploadEvidenceState): UnrecoverableFailure {
        return UnrecoverableFailure(retryState, params)
    }

    context(uploadEvidenceState: UploadEvidenceState)
    fun unrecoverableFailureFromCurrent(params: UnrecoverableFailure.Params): UnrecoverableFailure {
        return UnrecoverableFailure(retryState = uploadEvidenceState, params)
    }
}
