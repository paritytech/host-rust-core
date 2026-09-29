package io.paritytech.polkadotapp.feature_people_impl.data.updaters.scope

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_people_api.data.repository.PersonIdRepository
import io.paritytech.polkadotapp.feature_people_api.data.updaters.scope.PersonIdScope
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flatMapLatest
import javax.inject.Inject

class RealPersonIdScope @Inject constructor(
    private val accountRepository: AccountRepository,
    private val personIdRepository: PersonIdRepository
) : PersonIdScope {
    override fun invalidationFlow(chain: Chain): Flow<PersonId?> {
        return accountRepository.walletAccountFlow().flatMapLatest {
            personIdRepository.personIdFlow()
        }
    }
}
