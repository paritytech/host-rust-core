package io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate

import io.novasama.substrate_sdk_android.hash.isPositive
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.models.ProofOfInkAllocation
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.EvidenceUploadingFailureReason
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.EvidenceUploadingNonTerminalState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.UnrecoverableFailure
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.UploadEvidenceState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.UploadEvidenceStateFactory
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.upload.getCurrentAllocation
import kotlinx.coroutines.flow.first

class AwaitStorageAuthorizationState(
    private val stateFactory: UploadEvidenceStateFactory,
) : EvidenceUploadingNonTerminalState() {
    companion object {
        val ID = "AwaitStorageAuthorizationState"
    }

    override val id = ID

    context(transition: UploadEvidenceState.Transition)
    override suspend fun performNonTerminalTransition(): Result<UploadEvidenceState> {
        awaitStorageAuthorization()

        return Result.success(determineNextState())
    }

    context(transition: UploadEvidenceState.Transition)
    private suspend fun awaitStorageAuthorization() {
        transition.uploadSession.subscriptions.await().bulletIn.authorization.first {
            it != null && it.extent.transactionsAllowance.isPositive()
        }
    }

    context(transition: UploadEvidenceState.Transition)
    private suspend fun determineNextState(): UploadEvidenceState {
        val allocation = transition.uploadSession.getCurrentAllocation()

        return when (allocation) {
            ProofOfInkAllocation.Initial -> stateFactory.storeFirstPhotoChunk()
            ProofOfInkAllocation.InitDone -> stateFactory.extendAllocation()
            ProofOfInkAllocation.Full -> stateFactory.storeFirstVideoChunk()
            null -> stateFactory.unrecoverableFailureFromCurrent(UnrecoverableFailure.Params(EvidenceUploadingFailureReason.NO_ALLOCATION))
        }
    }
}
