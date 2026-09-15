package io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction

import io.paritytech.polkadotapp.common.utils.CoroutineDispatchers
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.CoinageTransactionService
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageAssetState
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageHandoffCommit
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageInput
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageOperationGroupId
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionId
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionRequest
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionState
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionStatus
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.OwnAsset
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.CoinageEntryRepository
import io.paritytech.polkadotapp.feature_coinage_impl.domain.coinageLogD
import io.paritytech.polkadotapp.feature_coinage_impl.domain.coinageLogI
import io.paritytech.polkadotapp.feature_coinage_impl.domain.coinageLogW
import io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.recovery.CoinageRecoveryLoop
import io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.recovery.CoinageRecoveryScheduler
import io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.registration.CoinageEntryRegistrar
import io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.submission.CoinageSubmissionTracker
import io.paritytech.polkadotapp.feature_transactions.api.data.EnrichedSendableExtrinsic
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Orchestrates registration, submission tracking and the recovery pass, and exposes the queries.
 *
 * It holds no durable state of its own: everything it knows lives in the ledger and everything volatile
 * lives in the collaborators, so process death loses exactly the volatile half — which is what makes
 * [close] a faithful crash in tests.
 */
@Singleton
class RealCoinageTransactionService @Inject constructor(
    private val registrar: CoinageEntryRegistrar,
    private val submissionTracker: CoinageSubmissionTracker,
    private val recoveryLoop: CoinageRecoveryLoop,
    private val recoveryScheduler: CoinageRecoveryScheduler,
    private val repository: CoinageEntryRepository,
    dispatchers: CoroutineDispatchers,
) : CoinageTransactionService {
    private val scope = CoroutineScope(SupervisorJob() + dispatchers.computation)

    override suspend fun submitTransaction(
        extrinsic: EnrichedSendableExtrinsic,
        inputs: List<CoinageInput>,
        outputs: List<OwnAsset>,
        groupId: CoinageOperationGroupId?,
    ): Result<CoinageTransactionId> {
        coinageLogI("submit-transaction inputs=${inputs.size} outputs=${outputs.size} group=${groupId?.value}")

        // Registration commits before submission, so there is never an extrinsic in flight without a record
        // holding its inputs. The reverse order would leave a window where a crash loses the lock for bytes
        // already on the wire.
        // No recovery is started here: registration hands the entry straight to the tracker, which owns it,
        // and a pass skips exactly the entries it owns. Recovery becomes this entry's business only when the
        // tracker lets go of it.
        return registrar.register(extrinsic, inputs, outputs, groupId).onSuccess { id ->
            submissionTracker.watch(scope, id, extrinsic) { onSubmissionReleased() }
        }.onFailure { coinageLogW("submit-transaction failed error=$it") }
    }

    override suspend fun submitTransactions(
        transactions: List<CoinageTransactionRequest>,
        groupId: CoinageOperationGroupId,
    ): Result<List<CoinageTransactionId>> {
        coinageLogI("submit-transactions count=${transactions.size} group=${groupId.value}")

        return registrar.registerAll(transactions, groupId).onSuccess { ids ->
            ids.zip(transactions).forEach { (id, transaction) ->
                submissionTracker.watch(scope, id, transaction.extrinsic) { onSubmissionReleased() }
            }
        }.onFailure { coinageLogW("submit-transactions failed group=${groupId.value} error=$it") }
    }

    override suspend fun preCommitHandoff(assets: List<OwnAsset>): Result<CoinageHandoffCommit> =
        registrar.preCommitHandoff(assets)

    override suspend fun releaseUncommittedHandoffs(): Result<Unit> = repository.releaseUncommittedHandoffs()

    override fun startRecovery() {
        coinageLogD("start-recovery")

        recoveryScheduler.ensureRunning()
    }

    private fun onSubmissionReleased() {
        // Send a re-run trigger in case loop is running right now, to save 1 block time latency
        recoveryLoop.manualTrigger()
        // Also schedule worker in case nothing is running
        startRecovery()
    }

    override suspend fun getTransactionStatus(id: CoinageTransactionId): Result<CoinageTransactionStatus> =
        repository.getStatus(id).mapCatching { it ?: error("No coinage transaction ${id.value}") }

    override fun subscribeTransactionStatus(id: CoinageTransactionId): Flow<CoinageTransactionStatus> =
        repository.subscribeStatus(id)

    override suspend fun getOperationGroupStatuses(
        groupId: CoinageOperationGroupId,
    ): Result<List<CoinageTransactionState>> = repository.getGroupStatuses(groupId)

    override fun subscribeOperationGroupStatuses(
        groupId: CoinageOperationGroupId,
    ): Flow<List<CoinageTransactionState>> = repository.subscribeGroupStatuses(groupId)

    override suspend fun getAssetState(asset: OwnAsset): Result<CoinageAssetState> =
        repository.getAssetState(asset)

    override suspend fun getAssetStates(assets: List<OwnAsset>): Result<Map<OwnAsset, CoinageAssetState>> =
        repository.getAssetStates(assets)

    override fun subscribeAssetStates(): Flow<Map<OwnAsset, CoinageAssetState>> =
        repository.subscribeAssetStates()

    /** Cancels every watcher and pass this instance owns. */
    fun close() {
        scope.cancel()
    }
}
