package io.paritytech.polkadotapp.feature_videogame_impl.domain.tracked

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.data.repository.getCandidateAccount
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.BandersnatchSecretsStorage
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.getAliasInContext
import io.paritytech.polkadotapp.feature_videogame_impl.data.ScoreContextProvider
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainAccountOrPerson
import javax.inject.Inject

/**
 * Resolves the `VideoGame.Players` key the current player is stored under — `Account(candidate)` normally, or
 * `Person(scoreAlias)` for an externally-recognized player. Mirrors what `subscribeOurPlayer` reads, so the
 * recorded override target matches the read-time key.
 */
class VideoGamePlayerKeyResolver @Inject constructor(
    private val accountRepository: AccountRepository,
    private val bandersnatchSecretsStorage: BandersnatchSecretsStorage,
    private val chainRegistry: ChainRegistry,
    private val scoreContextProvider: ScoreContextProvider,
) {
    suspend fun resolve(externallyRecognized: Boolean): OnChainAccountOrPerson {
        val candidate = accountRepository.getCandidateAccount()

        return if (externallyRecognized) {
            val alias = bandersnatchSecretsStorage.getAliasInContext(candidate.id, scoreContextProvider.context())
            OnChainAccountOrPerson.Person(alias)
        } else {
            val chain = chainRegistry.peopleChain()
            OnChainAccountOrPerson.Account(candidate.accountIdIn(chain))
        }
    }
}
