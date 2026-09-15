package io.paritytech.polkadotapp.feature_coinage_impl.data.transaction

import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageAssetState
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageOperationGroupId
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionId
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionState
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionStatus
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.OwnAsset
import kotlinx.coroutines.flow.Flow

/** Query helpers usable inside [CoinageEntryRepository.registerValidated]'s transaction. */
interface RegistrationValidationScope {
    /** Of [keys], those already minted by some entry. */
    suspend fun filterMinted(keys: List<AssetPublicKey>): Set<AssetPublicKey>

    /** Of [keys], those that are a key a peer sent us. */
    suspend fun filterReceived(keys: List<AssetPublicKey>): Set<AssetPublicKey>

    /** Of [keys], those already claimed by an entry that has not failed. */
    suspend fun filterClaimed(keys: List<AssetPublicKey>): Set<AssetPublicKey>

    /** Of [keys], those whose key has left the device. */
    suspend fun filterHandedOff(keys: List<AssetPublicKey>): Set<AssetPublicKey>
}

interface CoinageEntryRepository {
    /**
     * Inserts [request] after running [validation] in the same transaction, so nothing can move the state
     * that [validation] checked. Throwing from [validation] rolls the whole thing back.
     *
     * [onCommitted] also runs inside the transaction, so a caller can take ownership of the entry before any
     * other reader can observe the row.
     */
    suspend fun registerValidated(
        request: EntryRegistration,
        validation: suspend RegistrationValidationScope.() -> Unit,
        onCommitted: suspend (CoinageTransactionId) -> Unit,
    ): Result<CoinageTransactionId>

    /**
     * The same, for several transactions that are one operation: either every one is recorded or none is.
     *
     * A caller that folds a group into a single verdict needs this — half a group in the ledger is
     * indistinguishable from a group whose other half failed on chain, and the two mean opposite things.
     */
    suspend fun registerAllValidated(
        requests: List<EntryRegistration>,
        validation: suspend RegistrationValidationScope.() -> Unit,
        onCommitted: suspend (List<CoinageTransactionId>) -> Unit,
    ): Result<List<CoinageTransactionId>>

    /**
     * Marks [assets] as gone from the device after running [validation] in the same transaction, so nothing
     * can claim them between the check and the mark. Throwing from [validation] rolls the whole thing back.
     */
    suspend fun markHandedOff(
        assets: List<LedgerAsset>,
        validation: suspend RegistrationValidationScope.() -> Unit,
    ): Result<Unit>

    /** Makes the marks on [keys] final. */
    suspend fun commitHandoffs(keys: List<AssetPublicKey>): Result<Unit>

    /** Drops every mark that was never committed — the payments behind them never happened. */
    suspend fun releaseUncommittedHandoffs(): Result<Unit>

    suspend fun getHandoffKeys(): Result<Set<AssetPublicKey>>

    suspend fun getEntry(id: CoinageTransactionId): Result<LedgerEntry?>

    suspend fun getAllEntries(): Result<List<LedgerEntry>>

    /** Whether any entry is still undecided, and so still worth spending a pass on. */
    suspend fun hasLiveEntries(): Result<Boolean>

    suspend fun getStatus(id: CoinageTransactionId): Result<CoinageTransactionStatus?>

    /** Writes only while the entry still reads [observed]. Returns whether it wrote. */
    suspend fun compareAndSetStatus(
        id: CoinageTransactionId,
        observed: CoinageTransactionStatus,
        verdict: Verdict,
    ): Result<Boolean>

    fun subscribeStatus(id: CoinageTransactionId): Flow<CoinageTransactionStatus>

    suspend fun getGroupStatuses(groupId: CoinageOperationGroupId): Result<List<CoinageTransactionState>>

    fun subscribeGroupStatuses(groupId: CoinageOperationGroupId): Flow<List<CoinageTransactionState>>

    fun subscribeAssetStates(): Flow<Map<OwnAsset, CoinageAssetState>>

    suspend fun getAssetState(asset: OwnAsset): Result<CoinageAssetState>

    /**
     * The state of each of [assets], including ones the ledger has never heard of — those come back
     * untracked, since it only holds assets some transaction of ours has touched.
     */
    suspend fun getAssetStates(assets: List<OwnAsset>): Result<Map<OwnAsset, CoinageAssetState>>
}
