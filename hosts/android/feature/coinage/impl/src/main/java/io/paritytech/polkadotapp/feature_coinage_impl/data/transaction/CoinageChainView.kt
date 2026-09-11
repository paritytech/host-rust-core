package io.paritytech.polkadotapp.feature_coinage_impl.data.transaction

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchPublicKey
import io.paritytech.polkadotapp.chains.multiNetwork.runtime.repository.ExtrinsicOutcome
import io.paritytech.polkadotapp.chains.network.binding.BlockHash
import io.paritytech.polkadotapp.chains.network.binding.BlockNumber
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.ValueExponent
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CheckpointBlock
import io.paritytech.polkadotapp.feature_coinage_impl.data.model.OnChainAliasState
import io.paritytech.polkadotapp.feature_coinage_impl.data.model.OnChainCoinInfo
import io.paritytech.polkadotapp.feature_members_api.data.model.RingPosition
import io.paritytech.polkadotapp.feature_transactions.api.domain.model.TransactionHash
import kotlinx.coroutines.flow.Flow
import java.math.BigInteger

/** The `RecyclerAliasStates` key: value exponent, recycler index, and the voucher's derived alias. */
data class RecyclerAliasKey(
    val valueExponent: BigInteger,
    val recyclerIndex: BigInteger,
    val alias: DataByteArray,
)

/** Where a transaction was found, and whether its dispatch succeeded there. */
sealed interface TransactionSearchResult {
    /** [outcome] is null when the events at [block] could not be read — inclusion is not success. */
    data class Found(val block: CheckpointBlock, val outcome: ExtrinsicOutcome?) : TransactionSearchResult

    /** [wholeRangeRead] is false when some block could not be read, so absence proves nothing. */
    data class NotFound(val wholeRangeRead: Boolean) : TransactionSearchResult
}

/**
 * One view of the chain, pinned for the length of a single recovery pass.
 *
 * Every batched read keeps one shape, so a caller never has to remember which map omits what:
 *
 * - `Result.failure` — the read failed. Nothing about any requested key is known.
 * - a successful map — **every requested key is present**. A `null` value is the chain holding no value for
 *   it, which is a real answer.
 *
 * The storage layer drops keys with no value from its response, so implementations must put them back.
 * Callers look up with `getValue`, which turns a violation of this into an exception rather than a verdict.
 */
interface CoinageChainView {
    val finalizedHead: CheckpointBlock

    val bestHead: CheckpointBlock

    suspend fun coinsAt(at: BlockHash, coins: List<AccountId>): Result<Map<AccountId, OnChainCoinInfo?>>

    /**
     * The denomination of the recycler each voucher is a member of, null when it is in none. That is not a
     * voucher that is gone — archival removes this entry while the voucher stays redeemable — so it reads as
     * unknown, and it is also why the collection id cannot be built for that voucher.
     */
    suspend fun recyclerMembershipsAt(
        at: BlockHash,
        memberKeys: List<BandersnatchPublicKey>,
    ): Result<Map<BandersnatchPublicKey, ValueExponent?>>

    /** Where each voucher of [memberships] sits in its collection at [at]; null when it is not a member there. */
    suspend fun ringPositionsAt(
        at: BlockHash,
        memberships: Map<BandersnatchPublicKey, ValueExponent>,
    ): Result<Map<BandersnatchPublicKey, RingPosition?>>

    suspend fun aliasStatesAt(
        at: BlockHash,
        keys: List<RecyclerAliasKey>,
    ): Result<Map<RecyclerAliasKey, OnChainAliasState?>>

    /** The canonical hash at [blockNumber], for checking that a block we recorded is still real. */
    suspend fun blockHashAt(blockNumber: Long): Result<BlockHash?>

    suspend fun blockNumberAt(hash: BlockHash): Result<Long?>

    /**
     * Whether [txHash] dispatched successfully at [at]. The index is resolved from the same block the events
     * are read from and never stored — a reorg reorders extrinsics, so a stored index would name someone
     * else's outcome. Null when the transaction is not in that block.
     */
    suspend fun dispatchOutcomeAt(at: BlockHash, txHash: TransactionHash): Result<ExtrinsicOutcome?>

    suspend fun getAppliedExtrinsicHashes(at: BlockHash): Result<List<TransactionHash>>

    /**
     * Looks for [txHash] in `[from … to]`, and reads its dispatch outcome where it is found.
     *
     * Callers bound [to] at the finalized head, so a hit is always finalized and a terminal verdict from it
     * rests on a finalized fact.
     */
    suspend fun searchForTransaction(
        fromBlockNumber: Long,
        toBlockNumber: Long,
        txHash: TransactionHash,
    ): TransactionSearchResult
}

/** Pins one view per pass, from a single connection. */
interface CoinageChainViewFactory {
    suspend fun pin(): Result<CoinageChainView>

    /**
     * Emits every newly finalized block, so recovery can run a pass exactly when the facts it reads can have
     * changed. The number is a tick and nothing more — each pass still pins its own view, because a header
     * carries no hash of itself and the best head has to be read regardless.
     */
    fun finalizedHeads(): Flow<BlockNumber>

    /**
     * Emits every new best block. `PENDING_SUCCESS` and payment status are read at the best head, so those
     * facts move here rather than at finality — several blocks earlier.
     */
    fun bestHeads(): Flow<BlockNumber>
}
