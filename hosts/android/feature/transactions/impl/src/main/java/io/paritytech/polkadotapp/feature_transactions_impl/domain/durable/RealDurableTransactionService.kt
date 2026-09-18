package io.paritytech.polkadotapp.feature_transactions_impl.domain.durable

import io.novasama.substrate_sdk_android.extensions.toHexString
import io.novasama.substrate_sdk_android.runtime.definitions.types.generics.DefaultSignedExtensions
import io.novasama.substrate_sdk_android.runtime.definitions.types.generics.Era
import io.novasama.substrate_sdk_android.runtime.definitions.types.generics.findExplicitOrNull
import io.novasama.substrate_sdk_android.runtime.extrinsic.signer.SendableExtrinsic
import io.paritytech.polkadotapp.chains.util.extrinsicHash
import io.paritytech.polkadotapp.common.utils.CoroutineDispatchers
import io.paritytech.polkadotapp.feature_transactions.api.data.EnrichedSendableExtrinsic
import io.paritytech.polkadotapp.feature_transactions.api.domain.durable.CheckpointBlock
import io.paritytech.polkadotapp.feature_transactions.api.domain.durable.DurableTransactionService
import io.paritytech.polkadotapp.feature_transactions.api.domain.durable.DurableTxId
import io.paritytech.polkadotapp.feature_transactions.api.domain.durable.DurableTxRegistrationError
import io.paritytech.polkadotapp.feature_transactions.api.domain.durable.DurableTxState
import io.paritytech.polkadotapp.feature_transactions.api.domain.durable.DurableTxStatus
import io.paritytech.polkadotapp.feature_transactions.api.domain.durable.OperationGroupId
import io.paritytech.polkadotapp.feature_transactions.api.domain.durable.RegistrationScope
import io.paritytech.polkadotapp.feature_transactions.api.domain.durable.TxDomainId
import io.paritytech.polkadotapp.feature_transactions_impl.data.durable.DurableTxRegistration
import io.paritytech.polkadotapp.feature_transactions_impl.data.durable.DurableTxRepository
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
class RealDurableTransactionService @Inject constructor(
    private val repository: DurableTxRepository,
    private val submissionTracker: DurableSubmissionTracker,
    private val submissionOwned: SubmissionOwnedTransactions,
    private val recoveryLoop: DurableRecoveryLoop,
    private val recoveryScheduler: DurableRecoveryScheduler,
    dispatchers: CoroutineDispatchers,
) : DurableTransactionService {
    private val scope = CoroutineScope(SupervisorJob() + dispatchers.computation)

    override suspend fun submit(
        domain: TxDomainId,
        extrinsic: EnrichedSendableExtrinsic,
        groupId: OperationGroupId?,
        onRegister: suspend RegistrationScope.(DurableTxId) -> Unit,
    ): Result<DurableTxId> {
        val registration = runCatching { extrinsic.toRegistration(domain, groupId) }
            .getOrElse { return Result.failure(it) }

        // Registration commits before submission, so there is never an extrinsic in flight without a record
        // holding what it consumes. The reverse order would leave a window where a crash loses the lock for
        // bytes already on the wire.
        return repository.register(registration) { id ->
            onRegister(id)
            // Taken inside the same transaction, so a committed row always has an owner and a pass can
            // never reach it before the watcher does.
            submissionOwned.acquire(id)
        }.onSuccess { id ->
            durabilityLogI(
                "entry-registered ${durabilityLogId(domain, id, registration.txHash, groupId)} " +
                    "checkpoint=${registration.checkpoint.blockNumber} mortality=${registration.mortalityBlocks} " +
                    "window=${registration.checkpoint.blockNumber}.." +
                    "${registration.checkpoint.blockNumber + registration.mortalityBlocks}"
            )
            submissionTracker.watch(scope, id, extrinsic) { onSubmissionReleased() }
        }.onFailure { durabilityLogW("submit failed domain=${domain.value} error=$it") }
    }

    override suspend fun submitAll(
        domain: TxDomainId,
        extrinsics: List<EnrichedSendableExtrinsic>,
        groupId: OperationGroupId,
        onRegister: suspend RegistrationScope.(List<DurableTxId>) -> Unit,
    ): Result<List<DurableTxId>> {
        val registrations = runCatching { extrinsics.map { it.toRegistration(domain, groupId) } }
            .getOrElse { return Result.failure(it) }

        return repository.registerAll(registrations) { ids ->
            onRegister(ids)
            ids.forEach { submissionOwned.acquire(it) }
        }.onSuccess { ids ->
            ids.zip(registrations).forEach { (id, registration) ->
                durabilityLogI(
                    "entry-registered ${durabilityLogId(domain, id, registration.txHash, groupId)} " +
                        "checkpoint=${registration.checkpoint.blockNumber} " +
                        "mortality=${registration.mortalityBlocks}"
                )
            }
            ids.zip(extrinsics).forEach { (id, extrinsic) ->
                submissionTracker.watch(scope, id, extrinsic) { onSubmissionReleased() }
            }
        }.onFailure { durabilityLogW("submitAll failed domain=${domain.value} group=${groupId.value} error=$it") }
    }

    override fun startRecovery() {
        durabilityLogD("start-recovery")

        recoveryScheduler.ensureRunning()
    }

    override suspend fun getStatus(id: DurableTxId): Result<DurableTxStatus> =
        repository.getStatus(id).mapCatching { it ?: error("No durable transaction ${id.value}") }

    override fun subscribeStatus(id: DurableTxId): Flow<DurableTxStatus> = repository.subscribeStatus(id)

    override suspend fun getGroupStates(
        domain: TxDomainId,
        groupId: OperationGroupId,
    ): Result<List<DurableTxState>> = repository.getGroupStates(domain, groupId)

    override fun subscribeGroupStates(
        domain: TxDomainId,
        groupId: OperationGroupId,
    ): Flow<List<DurableTxState>> = repository.subscribeGroupStates(domain, groupId)

    private fun onSubmissionReleased() {
        // Save a block of latency if a loop is already running, and schedule the worker in case none is.
        recoveryLoop.manualTrigger()
        startRecovery()
    }

    /** Cancels every watcher and pass this instance owns. */
    fun close() {
        scope.cancel()
    }

    /**
     * The window is the extrinsic's own: its `CheckMortality` era is what the runtime will actually
     * enforce, so anchoring to anything else would search a range the extrinsic could not have landed in.
     * The anchor is read off the request rather than re-derived — re-deriving it from a head read at
     * registration time can name a different block once the head has crossed a period boundary.
     */
    private fun EnrichedSendableExtrinsic.toRegistration(
        domain: TxDomainId,
        groupId: OperationGroupId?,
    ): DurableTxRegistration {
        val era = mortalEra() ?: throw DurableTxRegistrationError.NotMortal
        val anchor = mortality.eraBlockNumber ?: throw DurableTxRegistrationError.MissingEraAnchor

        return DurableTxRegistration(
            domainId = domain,
            groupId = groupId,
            txHash = extrinsicHex.extrinsicHash(),
            checkpoint = CheckpointBlock(anchor, mortality.blockHash.value.toHexString(withPrefix = true)),
            mortalityBlocks = era.period.toLong(),
        )
    }
}

/** The runtime enforces this era, so it is the only window a transaction may be recovered against. */
private fun SendableExtrinsic.mortalEra(): Era.Mortal? =
    extrinsic.findExplicitOrNull(DefaultSignedExtensions.CHECK_MORTALITY) as? Era.Mortal
