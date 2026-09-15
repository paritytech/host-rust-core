package io.paritytech.polkadotapp.feature_wallet_impl.domain.interactor

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.data.network.TestnetEnvironment
import io.paritytech.polkadotapp.common.utils.filterResultSuccess
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.feature_coinage_api.domain.CoinsInteractor
import io.paritytech.polkadotapp.feature_coinage_api.domain.RecyclerVouchersInteractor
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.BackupProgress
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.Coin
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.RecyclerVoucher
import io.paritytech.polkadotapp.feature_coinage_api.domain.service.CoinageBackupService
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.CoinageRecyclingUseCase
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.CoinageTestnetFundUseCase
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.ShareCoinageLogsUseCase
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.TotalBalanceUseCase
import io.paritytech.polkadotapp.feature_products_api.domain.FundingDomainProvider
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_tokens_api.di.DigitalDollarChainAssetProvider
import io.paritytech.polkadotapp.feature_tokens_api.domain.ChainAssetProvider
import io.paritytech.polkadotapp.feature_wallet_impl.domain.model.AssetInfo
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject

class DigitalDollarCardDetailsInteractor @Inject constructor(
    @param:DigitalDollarChainAssetProvider private val chainAssetProvider: ChainAssetProvider,
    private val totalBalanceUseCase: TotalBalanceUseCase,
    private val environment: TestnetEnvironment,
    private val coinsInteractor: CoinsInteractor,
    private val recyclerVouchersInteractor: RecyclerVouchersInteractor,
    private val coinageTestnetFundUseCase: CoinageTestnetFundUseCase,
    private val shareCoinageLogsUseCase: ShareCoinageLogsUseCase,
    private val coinageRecyclingUseCase: CoinageRecyclingUseCase,
    private val coinageBackupService: CoinageBackupService,
    private val fundingDomainProvider: FundingDomainProvider
) {
    companion object {
        private val TOP_UP_AMOUNT = 150.toBigDecimal()
        private val NIGHTLY_TOP_UP_AMOUNT = 10.toBigDecimal()
    }

    suspend fun getCashProductId(): Result<ProductId> = fundingDomainProvider.getFundingProductId()

    fun observeAssetInfo(): Flow<AssetInfo> = flow {
        val asset = chainAssetProvider.asset()
        emitAll(createAssetInfoFlow(asset))
    }

    fun observeCoins(): Flow<List<Coin>> = coinsInteractor.subscribeCoins()

    fun observeVouchers(): Flow<List<RecyclerVoucher>> = recyclerVouchersInteractor.subscribeVouchers()

    fun observeActionsEnabled(): Flow<Boolean> = coinageBackupService.subscribeProgress()
        .map { it.actionsEnabled() }

    fun observeBackupProgress(): Flow<BackupProgress> = coinageBackupService.subscribeProgress()

    context(scope: ComputationalScope)
    fun startDeepSearch() = coinageBackupService.deepSearch()

    context(scope: ComputationalScope)
    fun markBackupCompleted() = coinageBackupService.markAsCompleted()

    suspend fun autoFundAvailable() = environment != TestnetEnvironment.PRODUCTION

    suspend fun testnetFund(): Result<Unit> {
        val amount = when (environment) {
            TestnetEnvironment.TESTNET -> TOP_UP_AMOUNT
            TestnetEnvironment.NIGHTLY, TestnetEnvironment.PRODUCTION -> NIGHTLY_TOP_UP_AMOUNT
        }

        return coinageTestnetFundUseCase(amount)
    }

    suspend fun shareCoinageLogs(): Result<Unit> = shareCoinageLogsUseCase().map { }

    suspend fun forceRecycle(coin: Coin): Result<Unit> = coinageRecyclingUseCase.recycle(listOf(coin)).map { }

    private fun createAssetInfoFlow(asset: Chain.Asset) = totalBalanceUseCase.subscribeTotalBalance()
        .logFailure("DigitalDollarCardDetailsInteractor: Failed to get coinage balance")
        .filterResultSuccess()
        .filterNotNull()
        .map { balance ->
            AssetInfo(
                asset = asset,
                totalBalance = balance.total,
                spendableBalance = balance.availablePrivate,
                gainingPrivacyBalance = balance.gainingPrivacy.amount,
                pendingBalance = balance.pending,
            )
        }

    private fun BackupProgress.actionsEnabled() = this !is BackupProgress.Initial && this !is BackupProgress.Deep
}
