package io.paritytech.polkadotapp.feature_coinage_api.domain.usecase

import io.paritytech.polkadotapp.feature_coinage_api.domain.model.CoinPrivateKey
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.CoinageTransferDetection
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageOperationGroupId
import kotlinx.coroutines.flow.Flow
import kotlin.time.ExperimentalTime
import kotlin.time.Instant

/**
 * Moves coins a peer handed us into our own coin set.
 *
 * The claims themselves are ordinary coinage transactions, so their outcome is the ledger's to decide: this
 * only detects what the keys control, submits, and reports what the ledger then says.
 */
interface ClaimReceivedCoinsUseCase {
    /**
     * Reports [CoinageTransferDetection.Transferred] as soon as a claim is included in a block, and keeps
     * emitting until the claim is over — so a fork that takes an inclusion away is reported too, as a return
     * to [CoinageTransferDetection.Detected].
     *
     * Claiming is not one-shot. A coin visible on chain that no claim of ours has taken is money the peer has
     * already parted with, and nothing else in the app will collect it, so a claim that failed is submitted
     * again whenever the chain still shows its coin unclaimed. The flow completes only when every coin has a
     * finalized claim, or when [retryUntil] has passed — and never before at least one attempt has been made,
     * so a message first seen after its window has closed is still tried once rather than abandoned.
     *
     * Because it ends only when nothing further will be attempted, completion is what tells a caller the
     * payment is finished. No status emitted along the way means that, a partial
     * [CoinageTransferDetection.Transferred] least of all.
     *
     * [groupId] must be derived from something stable about the payment — a chat message's id, the coin keys
     * themselves — because a second call with the same id rejoins the claims already submitted instead of
     * submitting them again. That is what makes a retry after process death safe.
     */
    @OptIn(ExperimentalTime::class)
    fun claim(
        coinKeys: List<CoinPrivateKey>,
        groupId: CoinageOperationGroupId,
        retryUntil: Instant,
    ): Flow<CoinageTransferDetection>
}
