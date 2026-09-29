package io.paritytech.polkadotapp.feature_videogame_impl.domain.usecase

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.data.repository.getCandidateAccount
import io.paritytech.polkadotapp.feature_account_api.domain.model.MetaAccount
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.VideoGamesProgressUseCase
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.isExternallyRecognized
import io.paritytech.polkadotapp.feature_videogame_impl.data.ScoreContextProvider
import timber.log.Timber
import javax.inject.Inject

interface PlayingAccountUseCase {
    context(scope: ComputationalScope)
    suspend fun getOurPlayerAccountId(): AccountId

    context(scope: ComputationalScope)
    suspend fun getPlayingAccount(): MetaAccount
}

class RealPlayingAccountUseCase @Inject constructor(
    private val gamesProgressUseCase: VideoGamesProgressUseCase,
    private val accountRepository: AccountRepository,
    private val chainRegistry: ChainRegistry,
    private val scoreContextProvider: ScoreContextProvider,
) : PlayingAccountUseCase {
    context(scope: ComputationalScope)
    override suspend fun getOurPlayerAccountId(): AccountId {
        return getPlayingAccount().accountIdIn(chainRegistry.peopleChain())
    }

    context(scope: ComputationalScope)
    override suspend fun getPlayingAccount(): MetaAccount {
        val gameProgress = gamesProgressUseCase.videoGameProgress()

        return if (gameProgress.isExternallyRecognized()) {
            Timber.d("Playing as person")

            accountRepository.getAliasAccount(scoreContextProvider.context())
        } else {
            Timber.d("Playing as account")

            accountRepository.getCandidateAccount()
        }
    }
}
