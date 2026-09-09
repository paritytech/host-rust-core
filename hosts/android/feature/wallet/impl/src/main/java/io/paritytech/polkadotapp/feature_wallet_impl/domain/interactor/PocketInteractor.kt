package io.paritytech.polkadotapp.feature_wallet_impl.domain.interactor

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.KnownChains
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.withAmount
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.utils.FeatureOption
import io.paritytech.polkadotapp.common.utils.filterResultSuccess
import io.paritytech.polkadotapp.common.utils.isEnabled
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.BackupProgress
import io.paritytech.polkadotapp.feature_coinage_api.domain.service.CoinageBackupService
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.TotalBalanceUseCase
import io.paritytech.polkadotapp.feature_tokens_api.di.DigitalDollarChainAssetProvider
import io.paritytech.polkadotapp.feature_tokens_api.domain.ChainAssetProvider
import io.paritytech.polkadotapp.feature_usernames_api.domain.usecase.UsernameOfAccountUseCase
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.VideoGamesProgressUseCase
import io.paritytech.polkadotapp.feature_wallet_impl.domain.model.DigitalDollarBalance
import io.paritytech.polkadotapp.feature_wallet_impl.domain.model.PocketRank
import io.paritytech.polkadotapp.feature_wallet_impl.domain.model.toPocketRank
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import javax.inject.Inject

class PocketInteractor @Inject constructor(
    @param:DigitalDollarChainAssetProvider private val chainAssetProvider: ChainAssetProvider,
    private val totalBalanceUseCase: TotalBalanceUseCase,
    private val usernameOfAccountUseCase: UsernameOfAccountUseCase,
    private val gamesProgressUseCase: VideoGamesProgressUseCase,
    private val coinageBackupService: CoinageBackupService,
    private val accountRepository: AccountRepository,
    private val chainRegistry: ChainRegistry,
    private val knownChains: KnownChains
) {
    fun observeBackupProgress(): Flow<BackupProgress> = coinageBackupService.subscribeProgress()

    fun observeAddress(): Flow<String> = flow { emit(getPeopleChainAddress()) }

    private suspend fun getPeopleChainAddress(): String {
        val walletAccount = accountRepository.getWalletAccount()
        val peopleChain = chainRegistry.getChain(knownChains.people)
        return walletAccount.addressIn(peopleChain)
    }

    fun observeDigitalDollarBalance(): Flow<DigitalDollarBalance> = flow {
        val asset = chainAssetProvider.asset()
        emitAll(
            totalBalanceUseCase.subscribeTotalBalance()
                .logFailure("PocketInteractor: Failed to get coinage balance")
                .filterResultSuccess()
                .filterNotNull()
                .map { balance ->
                    DigitalDollarBalance(
                        total = asset.withAmount(balance.total),
                        available = asset.withAmount(balance.available)
                    )
                }
        )
    }

    fun observeUsername(): Flow<String> = usernameOfAccountUseCase()
        .filterNotNull()
        .map { it.username.getDisplayUsername() }

    context(scope: ComputationalScope)
    fun observeRank(): Flow<PocketRank> = if (FeatureOption.PERSONHOOD.isEnabled) {
        gamesProgressUseCase.videoGamesProgressFlow().map { it.toPocketRank() }
    } else {
        flowOf(PocketRank.Basic)
    }
}
