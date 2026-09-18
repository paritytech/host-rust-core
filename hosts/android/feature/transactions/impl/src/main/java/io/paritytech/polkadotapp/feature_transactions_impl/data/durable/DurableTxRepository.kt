package io.paritytech.polkadotapp.feature_transactions_impl.data.durable

import io.paritytech.polkadotapp.database.dao.DurableTxDao
import io.paritytech.polkadotapp.database.model.BlockRefLocal
import io.paritytech.polkadotapp.database.model.DurableTxLocal
import io.paritytech.polkadotapp.feature_transactions.api.domain.durable.CheckpointBlock
import io.paritytech.polkadotapp.feature_transactions.api.domain.durable.DurableTxEntry
import io.paritytech.polkadotapp.feature_transactions.api.domain.durable.DurableTxId
import io.paritytech.polkadotapp.feature_transactions.api.domain.durable.DurableTxState
import io.paritytech.polkadotapp.feature_transactions.api.domain.durable.DurableTxStatus
import io.paritytech.polkadotapp.feature_transactions.api.domain.durable.OperationGroupId
import io.paritytech.polkadotapp.feature_transactions.api.domain.durable.RegistrationScope
import io.paritytech.polkadotapp.feature_transactions.api.domain.durable.TxDomainId
import io.paritytech.polkadotapp.feature_transactions.api.domain.durable.Verdict
import io.paritytech.polkadotapp.feature_transactions.api.domain.model.TransactionHash
import io.paritytech.polkadotapp.feature_transactions_impl.domain.durable.durabilityLogI
import io.paritytech.polkadotapp.feature_transactions_impl.domain.durable.durabilityLogW
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.map
import javax.inject.Inject

/** What registration needs to write one transaction row. */
class DurableTxRegistration(
    val domainId: TxDomainId,
    val groupId: OperationGroupId?,
    val txHash: TransactionHash,
    val checkpoint: CheckpointBlock,
    val mortalityBlocks: Long,
)

/**
 * The engine's durable ledger: one row per transaction it has taken responsibility for.
 *
 * It stores nothing domain-shaped. A domain writes its own rows through [RegistrationScope], inside the
 * same database transaction, so the two commit together.
 */
interface DurableTxRepository {
    /**
     * Inserts [registration], runs [onRegister] in the same transaction, and commits both.
     *
     * Throwing from [onRegister] rolls the whole thing back, which is how a domain rejects a registration
     * its own invariants forbid.
     */
    suspend fun register(
        registration: DurableTxRegistration,
        onRegister: suspend RegistrationScope.(DurableTxId) -> Unit,
    ): Result<DurableTxId>

    /** All of [registrations] or none: half a group in the ledger means the opposite of what it looks like. */
    suspend fun registerAll(
        registrations: List<DurableTxRegistration>,
        onRegister: suspend RegistrationScope.(List<DurableTxId>) -> Unit,
    ): Result<List<DurableTxId>>

    suspend fun getEntry(id: DurableTxId): Result<DurableTxEntry?>

    suspend fun getAllEntries(domainId: TxDomainId): Result<List<DurableTxEntry>>

    suspend fun getStatus(id: DurableTxId): Result<DurableTxStatus?>

    fun subscribeStatus(id: DurableTxId): Flow<DurableTxStatus>

    /** Writes only while the transaction still reads [observed]. Returns whether it wrote. */
    suspend fun compareAndSetStatus(
        id: DurableTxId,
        observed: DurableTxStatus,
        verdict: Verdict,
    ): Result<Boolean>

    suspend fun hasLiveTransactions(): Result<Boolean>

    /** Domains with something a pass could still decide. */
    suspend fun liveDomains(): Result<List<TxDomainId>>

    suspend fun getGroupStates(domainId: TxDomainId, groupId: OperationGroupId): Result<List<DurableTxState>>

    fun subscribeGroupStates(domainId: TxDomainId, groupId: OperationGroupId): Flow<List<DurableTxState>>
}

class RealDurableTxRepository @Inject constructor(
    private val dao: DurableTxDao,
) : DurableTxRepository {
    override suspend fun register(
        registration: DurableTxRegistration,
        onRegister: suspend RegistrationScope.(DurableTxId) -> Unit,
    ): Result<DurableTxId> = runCatching {
        var id = DurableTxId(DurableTxLocal.UNSAVED_ID)

        dao.withTransaction {
            id = DurableTxId(dao.insert(registration.toLocal()))
            RegistrationScope.onRegister(id)
        }

        id
    }

    override suspend fun registerAll(
        registrations: List<DurableTxRegistration>,
        onRegister: suspend RegistrationScope.(List<DurableTxId>) -> Unit,
    ): Result<List<DurableTxId>> = runCatching {
        val ids = mutableListOf<DurableTxId>()

        dao.withTransaction {
            registrations.mapTo(ids) { DurableTxId(dao.insert(it.toLocal())) }
            RegistrationScope.onRegister(ids)
        }

        ids
    }

    override suspend fun getEntry(id: DurableTxId): Result<DurableTxEntry?> =
        runCatching { dao.get(id.value)?.toEntry() }

    override suspend fun getAllEntries(domainId: TxDomainId): Result<List<DurableTxEntry>> =
        runCatching { dao.getAll(domainId.value).map { it.toEntry() } }

    override suspend fun getStatus(id: DurableTxId): Result<DurableTxStatus?> =
        runCatching { dao.getStatus(id.value)?.toDomain() }

    override fun subscribeStatus(id: DurableTxId): Flow<DurableTxStatus> =
        dao.subscribeStatus(id.value).filterNotNull().map { it.toDomain() }

    override suspend fun compareAndSetStatus(
        id: DurableTxId,
        observed: DurableTxStatus,
        verdict: Verdict,
    ): Result<Boolean> = runCatching {
        val written = dao.compareAndSetStatus(
            id = id.value,
            expected = observed.toLocal(),
            status = verdict.status.toLocal(),
            successDetectedBlockNumber = verdict.successDetectedAt?.blockNumber,
            successDetectedBlockHash = verdict.successDetectedAt?.blockHash,
        )

        val record = verdict.successDetectedAt?.blockNumber?.toString() ?: "none"

        if (written > 0) {
            durabilityLogI("entry=${id.value} cas-written from=$observed to=${verdict.status} record=$record")
        } else {
            durabilityLogW("entry=${id.value} cas-declined observed=$observed to=${verdict.status} record=$record")
        }

        written > 0
    }

    override suspend fun hasLiveTransactions(): Result<Boolean> = runCatching { dao.hasLiveTransactions() }

    override suspend fun liveDomains(): Result<List<TxDomainId>> =
        runCatching { dao.liveDomains().map(::TxDomainId) }

    override suspend fun getGroupStates(
        domainId: TxDomainId,
        groupId: OperationGroupId,
    ): Result<List<DurableTxState>> = runCatching {
        dao.getGroup(domainId.value, groupId.value).map { it.toState() }
    }

    override fun subscribeGroupStates(
        domainId: TxDomainId,
        groupId: OperationGroupId,
    ): Flow<List<DurableTxState>> =
        dao.subscribeGroup(domainId.value, groupId.value).map { rows -> rows.map { it.toState() } }

    private fun DurableTxRegistration.toLocal() = DurableTxLocal(
        id = DurableTxLocal.UNSAVED_ID,
        domainId = domainId.value,
        operationGroupId = groupId?.value,
        txHash = txHash,
        checkpoint = BlockRefLocal(checkpoint.blockNumber, checkpoint.blockHash),
        mortalityBlocks = mortalityBlocks,
        successDetectedAt = null,
        status = DurableTxLocal.Status.PENDING,
    )

    private fun DurableTxLocal.toEntry() = DurableTxEntry(
        id = DurableTxId(id),
        domainId = TxDomainId(domainId),
        groupId = operationGroupId?.let(::OperationGroupId),
        txHash = txHash,
        checkpoint = CheckpointBlock(checkpoint.blockNumber, checkpoint.blockHash),
        mortalityBlocks = mortalityBlocks,
        status = status.toDomain(),
        successDetectedAt = successDetectedAt?.let { CheckpointBlock(it.blockNumber, it.blockHash) },
    )

    private fun DurableTxLocal.toState() = DurableTxState(DurableTxId(id), status.toDomain())

    private fun DurableTxLocal.Status.toDomain() = when (this) {
        DurableTxLocal.Status.PENDING -> DurableTxStatus.PENDING
        DurableTxLocal.Status.PENDING_SUCCESS -> DurableTxStatus.PENDING_SUCCESS
        DurableTxLocal.Status.FINALIZED_SUCCESS -> DurableTxStatus.FINALIZED_SUCCESS
        DurableTxLocal.Status.FAILURE -> DurableTxStatus.FAILURE
    }

    private fun DurableTxStatus.toLocal() = when (this) {
        DurableTxStatus.PENDING -> DurableTxLocal.Status.PENDING
        DurableTxStatus.PENDING_SUCCESS -> DurableTxLocal.Status.PENDING_SUCCESS
        DurableTxStatus.FINALIZED_SUCCESS -> DurableTxLocal.Status.FINALIZED_SUCCESS
        DurableTxStatus.FAILURE -> DurableTxLocal.Status.FAILURE
    }
}
