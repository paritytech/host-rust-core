package io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.harness

import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageAssetState
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageInput
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageOperationGroupId
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionId
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionState
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionStatus
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.OwnAsset
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.AssetPublicKey
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.CoinageAssetKind
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.CoinageEntryRepository
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.EntryRegistration
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.LedgerAsset
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.LedgerEntry
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.RegistrationValidationScope
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.Verdict
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

private data class HandoffRow(val asset: OwnAsset, val committed: Boolean)

/**
 * The ledger, in memory, standing in for Room so a crash can be modelled as dropping everything volatile
 * while this store survives.
 *
 * The three validating writes take a snapshot and restore it if the validation or the commit hook throws,
 * which is the only way a caller can observe SQLite's rollback. Asset state is derived on read, exactly as
 * `ASSET_STATE_QUERY` derives it: the key space is the union of outputs, own inputs and handoff marks, and
 * each of the three facts is a separate lookup over that space.
 */
class InMemoryCoinageEntryRepository : CoinageEntryRepository {
    private val mutex = Mutex()
    private val revisions = MutableStateFlow(0)

    private var entries: List<LedgerEntry> = emptyList()
    private var handoffs: Map<AssetPublicKey, HandoffRow> = emptyMap()
    private var nextId = 1L

    override suspend fun registerValidated(
        request: EntryRegistration,
        validation: suspend RegistrationValidationScope.() -> Unit,
        onCommitted: suspend (CoinageTransactionId) -> Unit,
    ): Result<CoinageTransactionId> = transaction {
        ValidationScope().validation()

        val id = insert(request)
        onCommitted(id)

        id
    }

    override suspend fun registerAllValidated(
        requests: List<EntryRegistration>,
        validation: suspend RegistrationValidationScope.() -> Unit,
        onCommitted: suspend (List<CoinageTransactionId>) -> Unit,
    ): Result<List<CoinageTransactionId>> = transaction {
        ValidationScope().validation()

        val ids = requests.map(::insert)
        onCommitted(ids)

        ids
    }

    override suspend fun markHandedOff(
        assets: List<LedgerAsset>,
        validation: suspend RegistrationValidationScope.() -> Unit,
    ): Result<Unit> = transaction {
        ValidationScope().validation()

        assets.forEach { asset ->
            val owned = asset.asset ?: return@forEach
            if (asset.publicKey !in handoffs) {
                handoffs = handoffs + (asset.publicKey to HandoffRow(owned, committed = false))
            }
        }
    }

    override suspend fun commitHandoffs(keys: List<AssetPublicKey>): Result<Unit> = transaction {
        handoffs = handoffs.mapValues { (key, row) -> if (key in keys) row.copy(committed = true) else row }
    }

    override suspend fun releaseUncommittedHandoffs(): Result<Unit> = transaction {
        handoffs = handoffs.filterValues { it.committed }
    }

    override suspend fun getHandoffKeys(): Result<Set<AssetPublicKey>> = read { handoffs.keys.toSet() }

    override suspend fun getEntry(id: CoinageTransactionId): Result<LedgerEntry?> = read {
        entries.firstOrNull { it.id == id }
    }

    override suspend fun getAllEntries(): Result<List<LedgerEntry>> = read { entries.sortedBy { it.id.value } }

    override suspend fun hasLiveEntries(): Result<Boolean> = read { entries.any { it.status.isLive } }

    override suspend fun getStatus(id: CoinageTransactionId): Result<CoinageTransactionStatus?> = read {
        entries.firstOrNull { it.id == id }?.status
    }

    override suspend fun compareAndSetStatus(
        id: CoinageTransactionId,
        observed: CoinageTransactionStatus,
        verdict: Verdict,
    ): Result<Boolean> = transaction {
        val entry = entries.firstOrNull { it.id == id }

        if (entry == null || entry.status != observed) {
            false
        } else {
            entries = entries.map {
                if (it.id == id) it.copy(status = verdict.status, successDetectedAt = verdict.successDetectedAt) else it
            }
            true
        }
    }

    override fun subscribeStatus(id: CoinageTransactionId): Flow<CoinageTransactionStatus> =
        revisions.map { entries.firstOrNull { it.id == id }?.status }.filterNotNull()

    override suspend fun getGroupStatuses(groupId: CoinageOperationGroupId): Result<List<CoinageTransactionState>> =
        read { groupStates(groupId) }

    override fun subscribeGroupStatuses(groupId: CoinageOperationGroupId): Flow<List<CoinageTransactionState>> =
        revisions.map { groupStates(groupId) }

    override fun subscribeAssetStates(): Flow<Map<OwnAsset, CoinageAssetState>> = revisions.map { assetStates() }

    override suspend fun getAssetState(asset: OwnAsset): Result<CoinageAssetState> =
        read { assetStates()[asset] ?: CoinageAssetState.UNTRACKED }

    override suspend fun getAssetStates(assets: List<OwnAsset>): Result<Map<OwnAsset, CoinageAssetState>> =
        read {
            val states = assetStates()

            assets.associateWith { states[it] ?: CoinageAssetState.UNTRACKED }
        }

    private fun insert(request: EntryRegistration): CoinageTransactionId {
        val id = CoinageTransactionId(nextId++)

        entries = entries + LedgerEntry(
            id = id,
            groupId = request.groupId,
            txHash = request.txHash,
            checkpoint = request.checkpoint,
            mortalityBlocks = request.mortalityBlocks,
            successDetectedAt = null,
            status = CoinageTransactionStatus.PENDING,
            inputs = request.inputs.map { LedgerAsset(it.input.kind(), it.input.ownOrNull(), it.publicKey) },
            outputs = request.outputs.map { LedgerAsset(it.output.kind(), it.output, it.publicKey) },
        )

        return id
    }

    private fun groupStates(groupId: CoinageOperationGroupId) = entries
        .filter { it.groupId == groupId }
        .sortedBy { it.id.value }
        .map { entry ->
            CoinageTransactionState(
                id = entry.id,
                status = entry.status,
                inputs = entry.inputs.map { it.toCoinageInput() },
                outputs = entry.outputs.mapNotNull { it.asset },
            )
        }

    private fun assetStates(): Map<OwnAsset, CoinageAssetState> {
        val keySpace = buildSet {
            entries.forEach { entry ->
                entry.outputs.forEach { it.asset?.let(::add) }
                entry.inputs.forEach { it.asset?.let(::add) }
            }
            handoffs.values.forEach { add(it.asset) }
        }

        return keySpace.associateWith { asset ->
            CoinageAssetState(
                handedOff = handoffs.values.any { it.asset == asset },
                minterStatus = entries.firstOrNull { entry -> entry.outputs.any { it.asset == asset } }?.status,
                consumerStatus = entries
                    .firstOrNull { entry ->
                        entry.status != CoinageTransactionStatus.FAILURE && entry.inputs.any { it.asset == asset }
                    }
                    ?.status,
            )
        }
    }

    private suspend fun <T> transaction(block: suspend () -> T): Result<T> = mutex.withLock {
        val entriesBefore = entries
        val handoffsBefore = handoffs
        val nextIdBefore = nextId

        runCatching { block() }
            .onSuccess { revisions.value++ }
            .onFailure {
                entries = entriesBefore
                handoffs = handoffsBefore
                nextId = nextIdBefore
            }
    }

    private suspend fun <T> read(block: () -> T): Result<T> = mutex.withLock { runCatching(block) }

    private inner class ValidationScope : RegistrationValidationScope {
        override suspend fun filterMinted(keys: List<AssetPublicKey>) =
            keys.filterTo(mutableSetOf()) { key -> entries.any { entry -> entry.outputs.any { it.publicKey == key } } }

        override suspend fun filterReceived(keys: List<AssetPublicKey>) =
            keys.filterTo(mutableSetOf()) { key ->
                entries.any { entry -> entry.inputs.any { it.publicKey == key && it.asset == null } }
            }

        override suspend fun filterClaimed(keys: List<AssetPublicKey>) =
            keys.filterTo(mutableSetOf()) { key ->
                entries.any { entry ->
                    entry.status != CoinageTransactionStatus.FAILURE && entry.inputs.any { it.publicKey == key }
                }
            }

        override suspend fun filterHandedOff(keys: List<AssetPublicKey>) = keys.filterTo(mutableSetOf()) { it in handoffs }
    }
}

/** The mirror of [CoinageInput.kind]/[CoinageInput.ownOrNull]: a null asset is a coin a peer sent us. */
private fun LedgerAsset.toCoinageInput(): CoinageInput = when (val ownAsset = asset) {
    is OwnAsset.Coin -> CoinageInput.Coin.Own(ownAsset.derivationIndex)
    is OwnAsset.Voucher -> CoinageInput.Voucher(ownAsset.ringVrfIndex)
    null -> CoinageInput.Coin.Received(publicKey)
}

private fun CoinageInput.kind() = when (this) {
    is CoinageInput.Coin -> CoinageAssetKind.COIN
    is CoinageInput.Voucher -> CoinageAssetKind.VOUCHER
}

private fun CoinageInput.ownOrNull(): OwnAsset? = when (this) {
    is CoinageInput.Coin.Own -> OwnAsset.Coin(derivationIndex)
    is CoinageInput.Coin.Received -> null
    is CoinageInput.Voucher -> OwnAsset.Voucher(ringVrfIndex)
}

private fun OwnAsset.kind() = when (this) {
    is OwnAsset.Coin -> CoinageAssetKind.COIN
    is OwnAsset.Voucher -> CoinageAssetKind.VOUCHER
}
