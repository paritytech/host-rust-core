package io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate

import io.paritytech.polkadotapp.common.data.worker.stateMachine.WorkerStateMachineState
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.models.ProofOfInkAllocation
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.notifications.EvidenceNotificationsPublisher
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.EvidenceUploadingNonTerminalState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.UploadEvidenceState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.UploadEvidenceStateFactory
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.AwaitExtendAllocationConfirmationState.Params
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.upload.EvidenceUploader
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.upload.allocation
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.upload.canIncreaseUploadQuota
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.upload.requireCurrentStorageAuthorization
import io.paritytech.polkadotapp.feature_transaction_storage_api.domain.model.increasedAllocationAfter
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import java.math.BigInteger

class ExtendAllocationState(
    private val stateFactory: UploadEvidenceStateFactory,
) : EvidenceUploadingNonTerminalState() {
    companion object {
        val ID = "ExtendAllocationState"
    }

    override val id = ID

    context(transition: UploadEvidenceState.Transition)
    override suspend fun performNonTerminalTransition(): Result<UploadEvidenceState> {
        // We immediately fail instead of waiting by subscription since approval of initial case to get full allocation is long process
        // So we don't want to consume user resources and our quota - better to schedule retry
        if (!transition.uploadSession.canIncreaseUploadQuota()) return Result.failure(IllegalStateException("Not yet ready to increase quota"))

        val currentAuthorizedTransactions = transition.uploadSession.requireCurrentStorageAuthorization().extent.transactionsAllowance

        return transition.uploadSession.increaseUploadQuota().map {
            val nextParams = Params(currentAuthorizedTransactions)
            stateFactory.awaitExtendAllocationConfirmation(nextParams)
        }
    }
}

class AwaitExtendAllocationConfirmationState(
    private val stateFactory: UploadEvidenceStateFactory,
    override val params: Params,
    private val evidenceNotificationsPublisher: EvidenceNotificationsPublisher
) : EvidenceUploadingNonTerminalState(), WorkerStateMachineState.WithParams<Params> {
    data class Params(val authorizedTransactionsBeforeSubmission: BigInteger)

    companion object {
        val ID = "AwaitExtendAllocationConfirmationState"
    }

    override val id = ID

    context(transition: UploadEvidenceState.Transition)
    override suspend fun performNonTerminalTransition(): Result<UploadEvidenceState> {
        awaitFullAllocation()

        evidenceNotificationsPublisher.publishPhotoAccepted()

        return Result.success(stateFactory.storeFirstVideoChunk())
    }

    context(transition: UploadEvidenceState.Transition)
    private suspend fun awaitFullAllocation() {
        val subscriptions = transition.uploadSession.subscriptions.await()

        subscriptions.awaitPeopleChainFullAllocation()
        subscriptions.awaitBulletInChainFullAllocation()
    }

    private suspend fun EvidenceUploader.UploadSession.Subscriptions.awaitPeopleChainFullAllocation() {
        people.allocation.first { it == ProofOfInkAllocation.Full }
    }

    private suspend fun EvidenceUploader.UploadSession.Subscriptions.awaitBulletInChainFullAllocation() {
        bulletIn.authorization.filterNotNull().first { it.increasedAllocationAfter(params.authorizedTransactionsBeforeSubmission) }
    }
}
