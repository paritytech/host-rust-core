package io.paritytech.polkadotapp.feature_coinage_api.domain.transaction

import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageAssetState
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageHandoffCommit
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageInput
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageOperationGroupId
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionId
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionRequest
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionState
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionStatus
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.OwnAsset
import io.paritytech.polkadotapp.feature_transactions.api.data.EnrichedSendableExtrinsic
import kotlinx.coroutines.flow.Flow

/**
 * Owns two facts: which assets carry a lock, and the status of each submitted coinage transaction. Balance,
 * coin selection and payment status are derived above this service by combining those with on-chain
 * presence, which this service never reads.
 *
 * Individual transactions are the unit; a group is only an index and is never folded into one verdict.
 */
interface CoinageTransactionService {
    /**
     * Registers an already-signed transaction, then starts submission. Returns once committed, which is
     * before the bytes reach the wire: no extrinsic is ever in flight without a record holding its inputs.
     *
     * The checkpoint is the finalized head at registration and the mortality comes from [extrinsic]'s era.
     *
     * Fails with [io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageRegistrationError]
     * when an invariant would break.
     */
    suspend fun submitTransaction(
        extrinsic: EnrichedSendableExtrinsic,
        inputs: List<CoinageInput>,
        outputs: List<OwnAsset>,
        groupId: CoinageOperationGroupId?,
    ): Result<CoinageTransactionId>

    /**
     * Registers several transactions as one operation: either all of them are recorded or none is.
     *
     * A caller that reads [groupId] back as a single outcome needs this — half a group in the ledger looks
     * exactly like a group whose other half failed on chain, and the two mean opposite things.
     */
    suspend fun submitTransactions(
        transactions: List<CoinageTransactionRequest>,
        groupId: CoinageOperationGroupId,
    ): Result<List<CoinageTransactionId>>

    /**
     * Reserves [assets] against being spent again, before their keys reach the transport — a key that arrives
     * at a peer without a mark can be selected again and double-spent.
     *
     * The reservation is provisional until the returned handle is committed, and a relaunch clears every
     * uncommitted one. That is what keeps a payment that failed after this point from freezing the coins: the
     * only way for a mark to outlive the process is for the keys to have actually left.
     */
    suspend fun preCommitHandoff(assets: List<OwnAsset>): Result<CoinageHandoffCommit>

    /** Clears the reservations of payments that never became durable. Runs once, on launch. */
    suspend fun releaseUncommittedHandoffs(): Result<Unit>

    /**
     * Ensures recovery is running: one pass per newly finalized block, until no entry is left undecided.
     *
     * Fire-and-forget and idempotent — a caller states that entries may need deciding, not that a pass should
     * happen now.
     */
    fun startRecovery()

    suspend fun getTransactionStatus(id: CoinageTransactionId): Result<CoinageTransactionStatus>

    fun subscribeTransactionStatus(id: CoinageTransactionId): Flow<CoinageTransactionStatus>

    /** In registration order. Empty when nothing was ever registered under [groupId]. */
    suspend fun getOperationGroupStatuses(groupId: CoinageOperationGroupId): Result<List<CoinageTransactionState>>

    /** In registration order. */
    fun subscribeOperationGroupStatuses(groupId: CoinageOperationGroupId): Flow<List<CoinageTransactionState>>

    suspend fun getAssetState(asset: OwnAsset): Result<CoinageAssetState>

    /** The state of each of [assets]; ones the ledger has never heard of come back untracked. */
    suspend fun getAssetStates(assets: List<OwnAsset>): Result<Map<OwnAsset, CoinageAssetState>>

    /** An asset absent from the map carries [CoinageAssetState.UNTRACKED]. */
    fun subscribeAssetStates(): Flow<Map<OwnAsset, CoinageAssetState>>
}

fun Map<OwnAsset, CoinageAssetState>.getStateOrUntracked(asset: OwnAsset): CoinageAssetState {
    return get(asset) ?: CoinageAssetState.UNTRACKED
}
