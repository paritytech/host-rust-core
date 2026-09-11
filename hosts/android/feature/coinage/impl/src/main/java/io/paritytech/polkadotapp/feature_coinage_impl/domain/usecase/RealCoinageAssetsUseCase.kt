package io.paritytech.polkadotapp.feature_coinage_impl.domain.usecase

import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.CoinageTransactionService
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageAssetState
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.OwnAsset
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.CoinageAssetsUseCase
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.TrackedCoin
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.TrackedVoucher
import io.paritytech.polkadotapp.feature_coinage_impl.data.repository.CoinRepository
import io.paritytech.polkadotapp.feature_coinage_impl.data.repository.VoucherRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.first
import javax.inject.Inject

/**
 * Every join here is deduplicated, because Room invalidates a query when its table is written rather than
 * when the rows it selected change. The presence sync writes every coin in the wallet and the ledger writes
 * on every status change, so without this one unrelated write re-runs the join for every caller — and
 * callers do real work per emission, up to reading the finalized chain.
 */
class RealCoinageAssetsUseCase @Inject constructor(
    private val coinRepository: CoinRepository,
    private val voucherRepository: VoucherRepository,
    private val transactionService: CoinageTransactionService,
) : CoinageAssetsUseCase {
    override fun subscribeCoins(): Flow<List<TrackedCoin>> = combine(
        coinRepository.subscribeAllCoins(),
        transactionService.subscribeAssetStates(),
    ) { coins, states ->
        coins.map { TrackedCoin(it, states.stateOf(OwnAsset.Coin(it.derivationIndex))) }
    }.distinctUntilChanged()

    override fun subscribeCoinsBy(accountIds: List<AccountId>): Flow<List<TrackedCoin>> = combine(
        coinRepository.subscribeCoinsBy(accountIds),
        transactionService.subscribeAssetStates(),
    ) { coins, states ->
        coins.map { TrackedCoin(it, states.stateOf(OwnAsset.Coin(it.derivationIndex))) }
    }.distinctUntilChanged()

    override suspend fun getCoins(): List<TrackedCoin> = subscribeCoins().first()

    override fun subscribeVouchers(): Flow<List<TrackedVoucher>> = combine(
        voucherRepository.subscribeAllVouchers(),
        transactionService.subscribeAssetStates(),
    ) { vouchers, states ->
        vouchers.map { TrackedVoucher(it, states.stateOf(OwnAsset.Voucher(it.ringVrfKeyIndex))) }
    }.distinctUntilChanged()

    override suspend fun getVouchers(): List<TrackedVoucher> = subscribeVouchers().first()
}

/** An asset the ledger has never heard of carries no claim, which is the same as a free one. */
private fun Map<OwnAsset, CoinageAssetState>.stateOf(asset: OwnAsset) =
    this[asset] ?: CoinageAssetState.UNTRACKED
