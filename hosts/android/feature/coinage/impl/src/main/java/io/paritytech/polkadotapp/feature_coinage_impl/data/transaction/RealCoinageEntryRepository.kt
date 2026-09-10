package io.paritytech.polkadotapp.feature_coinage_impl.data.transaction

import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import io.paritytech.polkadotapp.database.dao.CoinageAssetStateProjection
import io.paritytech.polkadotapp.database.dao.CoinageEntryDao
import io.paritytech.polkadotapp.database.dao.CoinageEntryWithAssets
import io.paritytech.polkadotapp.database.model.BlockRefLocal
import io.paritytech.polkadotapp.database.model.CoinageEntryInputLocal
import io.paritytech.polkadotapp.database.model.CoinageEntryLocal
import io.paritytech.polkadotapp.database.model.CoinageEntryOutputLocal
import io.paritytech.polkadotapp.database.model.CoinageHandoffLocal
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CheckpointBlock
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageAssetState
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageInput
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageOperationGroupId
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionId
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionState
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionStatus
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.OwnAsset
import io.paritytech.polkadotapp.feature_coinage_impl.domain.coinageLogI
import io.paritytech.polkadotapp.feature_coinage_impl.domain.coinageLogW
import io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.coinageLogId
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.map
import javax.inject.Inject

class RealCoinageEntryRepository @Inject constructor(
    private val dao: CoinageEntryDao,
) : CoinageEntryRepository {
    override suspend fun registerValidated(
        request: EntryRegistration,
        validation: suspend RegistrationValidationScope.() -> Unit,
        onCommitted: suspend (CoinageTransactionId) -> Unit,
    ): Result<CoinageTransactionId> = runCatching {
        var id = CoinageTransactionId(CoinageEntryLocal.UNSAVED_ID)

        dao.withTransaction {
            DaoValidationScope(dao).validation()

            id = CoinageTransactionId(
                dao.insertEntry(
                    entry = request.toLocal(),
                    inputs = { entryId -> request.inputs.mapIndexed { position, it -> it.toLocal(entryId, position) } },
                    outputs = { entryId -> request.outputs.mapIndexed { position, it -> it.toLocal(entryId, position) } },
                )
            )

            onCommitted(id)
        }

        id
    }

    override suspend fun registerAllValidated(
        requests: List<EntryRegistration>,
        validation: suspend RegistrationValidationScope.() -> Unit,
        onCommitted: suspend (List<CoinageTransactionId>) -> Unit,
    ): Result<List<CoinageTransactionId>> = runCatching {
        val ids = mutableListOf<CoinageTransactionId>()

        dao.withTransaction {
            DaoValidationScope(dao).validation()

            requests.mapTo(ids) { request ->
                CoinageTransactionId(
                    dao.insertEntry(
                        entry = request.toLocal(),
                        inputs = { id -> request.inputs.mapIndexed { position, it -> it.toLocal(id, position) } },
                        outputs = { id -> request.outputs.mapIndexed { position, it -> it.toLocal(id, position) } },
                    )
                )
            }

            onCommitted(ids)
        }

        ids
    }

    override suspend fun markHandedOff(
        assets: List<LedgerAsset>,
        validation: suspend RegistrationValidationScope.() -> Unit,
    ): Result<Unit> = runCatching {
        dao.withTransaction {
            DaoValidationScope(dao).validation()
            dao.insertHandoffs(assets.mapNotNull { it.toHandoffLocal() })
        }
    }

    override suspend fun commitHandoffs(keys: List<AssetPublicKey>): Result<Unit> = runCatching {
        dao.commitHandoffs(keys.map { it.value })
    }

    override suspend fun releaseUncommittedHandoffs(): Result<Unit> = runCatching {
        dao.deleteUncommittedHandoffs()
    }

    override suspend fun getHandoffKeys(): Result<Set<AssetPublicKey>> = runCatching {
        dao.getHandoffs().mapTo(mutableSetOf()) { it.onChainKey.toDataByteArray() }
    }

    override suspend fun getEntry(id: CoinageTransactionId): Result<LedgerEntry?> = runCatching {
        dao.getEntry(id.value)?.toDomain()
    }

    override suspend fun getAllEntries(): Result<List<LedgerEntry>> = runCatching {
        dao.getAllEntries().map { it.toDomain() }
    }

    override suspend fun hasLiveEntries(): Result<Boolean> = runCatching {
        dao.hasLiveEntries()
    }

    override suspend fun getStatus(id: CoinageTransactionId): Result<CoinageTransactionStatus?> = runCatching {
        dao.getStatus(id.value)?.toDomain()
    }

    override suspend fun compareAndSetStatus(
        id: CoinageTransactionId,
        observed: CoinageTransactionStatus,
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
            coinageLogI("${coinageLogId(id)} cas-written from=$observed to=${verdict.status} record=$record")
        } else {
            coinageLogW("${coinageLogId(id)} cas-declined observed=$observed to=${verdict.status} record=$record")
        }

        written > 0
    }

    override fun subscribeStatus(id: CoinageTransactionId): Flow<CoinageTransactionStatus> {
        return dao.subscribeStatus(id.value).filterNotNull().map { it.toDomain() }
    }

    override suspend fun getGroupStatuses(
        groupId: CoinageOperationGroupId,
    ): Result<List<CoinageTransactionState>> = runCatching {
        dao.getGroupEntries(groupId.value).toTransactionStates()
    }

    override fun subscribeGroupStatuses(groupId: CoinageOperationGroupId): Flow<List<CoinageTransactionState>> {
        return dao.subscribeGroupEntries(groupId.value).map { it.toTransactionStates() }
    }

    override fun subscribeAssetStates(): Flow<Map<OwnAsset, CoinageAssetState>> {
        return dao.subscribeAssetStates().map { projections -> projections.associate { it.toDomain() } }
    }

    override suspend fun getAssetState(asset: OwnAsset): Result<CoinageAssetState> = runCatching {
        dao.getAssetState(asset.kind().toLocal(), asset.index())?.toDomain()?.second ?: CoinageAssetState.UNTRACKED
    }

    override suspend fun getAssetStates(assets: List<OwnAsset>): Result<Map<OwnAsset, CoinageAssetState>> =
        runCatching {
            val tracked = assets.groupBy { it.kind() }
                .flatMap { (kind, ofKind) -> dao.getAssetStates(kind.toLocal(), ofKind.map { it.index() }) }
                .associate { it.toDomain() }

            assets.associateWith { tracked[it] ?: CoinageAssetState.UNTRACKED }
        }
}

private class DaoValidationScope(private val dao: CoinageEntryDao) : RegistrationValidationScope {
    override suspend fun filterMinted(keys: List<AssetPublicKey>) = dao.filterMinted(keys.raw()).wrap()

    override suspend fun filterReceived(keys: List<AssetPublicKey>) = dao.filterReceivedKeys(keys.raw()).wrap()

    override suspend fun filterClaimed(keys: List<AssetPublicKey>) = dao.filterClaimed(keys.raw()).wrap()

    override suspend fun filterHandedOff(keys: List<AssetPublicKey>) = dao.filterHandedOff(keys.raw()).wrap()

    private fun List<AssetPublicKey>.raw() = map { it.value }

    private fun List<ByteArray>.wrap() = mapTo(mutableSetOf()) { it.toDataByteArray() }
}

private fun EntryRegistration.toLocal() = CoinageEntryLocal(
    id = CoinageEntryLocal.UNSAVED_ID,
    operationGroupId = groupId?.value,
    txHash = txHash,
    checkpoint = checkpoint.toLocal(),
    mortalityBlocks = mortalityBlocks,
    successDetectedAt = null,
    status = CoinageEntryLocal.Status.PENDING,
)

private fun RegistrationInput.toLocal(entryId: Long, position: Int) = CoinageEntryInputLocal(
    entryId = entryId,
    position = position,
    assetKind = input.kind().toLocal(),
    derivationIndex = input.indexOrNull(),
    onChainKey = publicKey.value,
)

private fun RegistrationOutput.toLocal(entryId: Long, position: Int) = CoinageEntryOutputLocal(
    entryId = entryId,
    position = position,
    assetKind = output.kind().toLocal(),
    derivationIndex = output.index(),
    onChainKey = publicKey.value,
)

private fun LedgerAsset.toHandoffLocal(): CoinageHandoffLocal? {
    val owned = asset ?: return null

    return CoinageHandoffLocal(
        onChainKey = publicKey.value,
        assetKind = owned.kind().toLocal(),
        derivationIndex = owned.index(),
        committed = false,
    )
}

private fun List<CoinageEntryWithAssets>.toTransactionStates() = map { it.toDomain() }.map { entry ->
    CoinageTransactionState(
        id = entry.id,
        status = entry.status,
        inputs = entry.inputs.map { it.toCoinageInput() },
        outputs = entry.outputs.mapNotNull { it.asset },
    )
}

/** A null [LedgerAsset.asset] is the peer-sent coin case: an on-chain identity we hold no local asset for. */
private fun LedgerAsset.toCoinageInput(): CoinageInput = when (val ownAsset = asset) {
    is OwnAsset.Coin -> CoinageInput.Coin.Own(ownAsset.derivationIndex)
    is OwnAsset.Voucher -> CoinageInput.Voucher(ownAsset.ringVrfIndex)
    null -> CoinageInput.Coin.Received(publicKey)
}

private fun CoinageEntryWithAssets.toDomain() = LedgerEntry(
    id = CoinageTransactionId(entry.id),
    groupId = entry.operationGroupId?.let(::CoinageOperationGroupId),
    txHash = entry.txHash,
    checkpoint = entry.checkpoint.toDomain(),
    mortalityBlocks = entry.mortalityBlocks,
    successDetectedAt = entry.successDetectedAt?.toDomain(),
    status = entry.status.toDomain(),
    inputs = inputs.sortedBy { it.position }.map { it.toLedgerAsset() },
    outputs = outputs.sortedBy { it.position }.map { it.toLedgerAsset() },
)

private fun CoinageEntryInputLocal.toLedgerAsset() = LedgerAsset(
    kind = assetKind.toDomain(),
    asset = derivationIndex?.let { assetKind.toOwnAsset(it) },
    publicKey = onChainKey.toDataByteArray(),
)

private fun CoinageEntryOutputLocal.toLedgerAsset() = LedgerAsset(
    kind = assetKind.toDomain(),
    asset = assetKind.toOwnAsset(derivationIndex),
    publicKey = onChainKey.toDataByteArray(),
)

private fun CoinageAssetStateProjection.toDomain(): Pair<OwnAsset, CoinageAssetState> =
    assetKind.toOwnAsset(derivationIndex) to CoinageAssetState(
        handedOff = handedOff,
        minterStatus = minterStatus?.toDomain(),
        consumerStatus = consumerStatus?.toDomain(),
    )

private fun CheckpointBlock.toLocal() = BlockRefLocal(blockNumber, blockHash)

private fun BlockRefLocal.toDomain() = CheckpointBlock(blockNumber, blockHash)

private fun CoinageEntryLocal.AssetKind.toOwnAsset(derivationIndex: Int): OwnAsset = when (this) {
    CoinageEntryLocal.AssetKind.COIN -> OwnAsset.Coin(derivationIndex)
    CoinageEntryLocal.AssetKind.VOUCHER -> OwnAsset.Voucher(derivationIndex)
}

private fun CoinageEntryLocal.AssetKind.toDomain() = when (this) {
    CoinageEntryLocal.AssetKind.COIN -> CoinageAssetKind.COIN
    CoinageEntryLocal.AssetKind.VOUCHER -> CoinageAssetKind.VOUCHER
}

private fun CoinageAssetKind.toLocal() = when (this) {
    CoinageAssetKind.COIN -> CoinageEntryLocal.AssetKind.COIN
    CoinageAssetKind.VOUCHER -> CoinageEntryLocal.AssetKind.VOUCHER
}

private fun OwnAsset.kind() = when (this) {
    is OwnAsset.Coin -> CoinageAssetKind.COIN
    is OwnAsset.Voucher -> CoinageAssetKind.VOUCHER
}

private fun OwnAsset.index() = when (this) {
    is OwnAsset.Coin -> derivationIndex
    is OwnAsset.Voucher -> ringVrfIndex
}

private fun CoinageInput.kind() = when (this) {
    is CoinageInput.Coin -> CoinageAssetKind.COIN
    is CoinageInput.Voucher -> CoinageAssetKind.VOUCHER
}

private fun CoinageInput.indexOrNull() = when (this) {
    is CoinageInput.Coin.Own -> derivationIndex
    is CoinageInput.Coin.Received -> null
    is CoinageInput.Voucher -> ringVrfIndex
}

private fun CoinageEntryLocal.Status.toDomain() = when (this) {
    CoinageEntryLocal.Status.PENDING -> CoinageTransactionStatus.PENDING
    CoinageEntryLocal.Status.PENDING_SUCCESS -> CoinageTransactionStatus.PENDING_SUCCESS
    CoinageEntryLocal.Status.FINALIZED_SUCCESS -> CoinageTransactionStatus.FINALIZED_SUCCESS
    CoinageEntryLocal.Status.FAILURE -> CoinageTransactionStatus.FAILURE
}

private fun CoinageTransactionStatus.toLocal() = when (this) {
    CoinageTransactionStatus.PENDING -> CoinageEntryLocal.Status.PENDING
    CoinageTransactionStatus.PENDING_SUCCESS -> CoinageEntryLocal.Status.PENDING_SUCCESS
    CoinageTransactionStatus.FINALIZED_SUCCESS -> CoinageEntryLocal.Status.FINALIZED_SUCCESS
    CoinageTransactionStatus.FAILURE -> CoinageEntryLocal.Status.FAILURE
}
