package io.paritytech.polkadotapp.feature_coinage_impl.domain.usecase

import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.hasEverBeenOnChain
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionStatus
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionStatus.FINALIZED_SUCCESS
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.CoinageAssetsUseCase
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.CoinagePaymentState
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.CoinagePaymentStatus
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.CoinagePaymentStatusUseCase
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.TrackedCoin
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.CoinageChainViewFactory
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject

/**
 * How a payment's coins look to the side that sent them.
 *
 * Two independent facts decide each coin — whether the chain holds it, and what the ledger says minted it —
 * and they arrive from separate streams. Paired at the best head they can disagree for a moment: the ledger
 * records a mint as included before the chain subscription reports the coin present, which reads as a coin
 * that existed and vanished. That is a fine guess to show and a terrible one to close a payment on, so
 * nothing read there is ever marked proven.
 *
 * Proof comes from the finalized chain, where both halves can be read at one vantage point.
 */
class RealCoinagePaymentStatusUseCase @Inject constructor(
    private val coinageAssetsUseCase: CoinageAssetsUseCase,
    private val chainViewFactory: CoinageChainViewFactory,
) : CoinagePaymentStatusUseCase {
    override fun subscribeStatuses(coins: List<AccountId>): Flow<Map<AccountId, CoinagePaymentState>> {
        return coinageAssetsUseCase.subscribeCoinsBy(coins).map { tracked ->
            val atFinalized = tracked.presenceAtFinalized()

            tracked.associate { it.coin.accountId to CoinagePaymentState(it.coin, it.paymentStatus(atFinalized)) }
        }
    }

    /**
     * Whether the finalized chain holds each coin whose mint finalized; absent from the map when unknown.
     *
     * Only those coins are worth asking about: one has to have been minted beyond recall before its absence
     * can mean the peer took it. A read that cannot be taken leaves them unknown, which costs a later look
     * and never a wrong verdict.
     */
    private suspend fun List<TrackedCoin>.presenceAtFinalized(): Map<AccountId, Boolean> {
        val minted = filter { it.state.minterStatus == FINALIZED_SUCCESS }
            .map { it.coin.accountId }

        if (minted.isEmpty()) return emptyMap()

        val view = chainViewFactory.pin().getOrNull() ?: return emptyMap()
        val coins = view.coinsAt(view.finalizedHead.blockHash, minted).getOrNull() ?: return emptyMap()

        return minted.associateWith { coins[it] != null }
    }
}

private fun TrackedCoin.paymentStatus(atFinalized: Map<AccountId, Boolean>): CoinagePaymentStatus = when {
    // Finalized minter and absence at finalized is guaranteed finalized claim
    state.minterStatus == FINALIZED_SUCCESS && atFinalized[coin.accountId] == false
    -> CoinagePaymentStatus.Claimed(finalized = true)

    // Never minted: the key the peer holds controls nothing, and nothing will change that.
    state.minterStatus == CoinageTransactionStatus.FAILURE -> CoinagePaymentStatus.Failed

    coin.isOnChain -> CoinagePaymentStatus.AwaitingClaim

    // We have previously seen coin on-chain and now its gone, but its minter has arrived
    // This wont fire if we never seen a coin: worst case we will be stuck at Detecting until finality decides
    coin.hasEverBeenOnChain && state.minterStatus?.isArrived == true ->
        CoinagePaymentStatus.Claimed(finalized = false)

    // We have not seen a coin unchain on best, but we can see it at finalized
    // Since we cant distinguish between "not on chain" and "we haven't yet synced with best chain" reporting Claimed here would be unsafe
    // So we play conservative and emit AwaitingClaim instead. After coin is gone from finalized block, next pass wil mark it as claimed
    atFinalized[coin.accountId] == true -> CoinagePaymentStatus.AwaitingClaim

    else -> CoinagePaymentStatus.Detecting
}
