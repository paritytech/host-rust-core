package io.paritytech.polkadotapp.feature_people_impl.domain.useCase

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchContext
import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.KnownChains
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.common.data.cache.CacheableDataConsistency
import io.paritytech.polkadotapp.common.utils.flowOfAll
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.data.repository.getCandidateAccount
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.BandersnatchSecretsStorage
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.getMemberKey
import io.paritytech.polkadotapp.feature_members_api.data.model.RingPosition
import io.paritytech.polkadotapp.feature_members_api.data.model.ringIndex
import io.paritytech.polkadotapp.feature_members_api.data.repository.MembersRepository
import io.paritytech.polkadotapp.feature_people_api.data.AliasContextProvider
import io.paritytech.polkadotapp.feature_people_api.data.SetAliasContext
import io.paritytech.polkadotapp.feature_people_api.data.model.PersonRecord
import io.paritytech.polkadotapp.feature_people_api.data.repository.PersonIdRepository
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonhoodStatus
import io.paritytech.polkadotapp.feature_people_api.domain.useCase.PersonStatusUseCase
import io.paritytech.polkadotapp.feature_people_impl.data.repository.PeopleRepository
import io.paritytech.polkadotapp.feature_people_impl.data.repository.subscribePersonMember
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.transformLatest
import javax.inject.Inject

class RealPersonStatusUseCase @Inject constructor(
    private val personIdRepository: PersonIdRepository,
    private val peopleRepository: PeopleRepository,
    private val membersRepository: MembersRepository,
    private val chainRegistry: ChainRegistry,
    private val knownChains: KnownChains,
    private val accountRepository: AccountRepository,
    private val bandersnatchSecretsStorage: BandersnatchSecretsStorage,
    @SetAliasContext private val assignableContexts: Set<@JvmSuppressWildcards AliasContextProvider>
) : PersonStatusUseCase {
    override fun personhoodStatusFlow(): Flow<PersonhoodStatus> = flowOfAll {
        val chain = peopleChain()

        getCandidateMemberRecord(chain).map {
            when (it) {
                null -> PersonhoodStatus.NotPerson
                is RingPosition.Suspended -> PersonhoodStatus.Suspended
                is RingPosition.Onboarding -> PersonhoodStatus.Onboarding
                is RingPosition.Included -> PersonhoodStatus.Active
            }
        }
    }

    override fun canUseAliasFlow(context: BandersnatchContext): Flow<Boolean> {
        return flowOfAll {
            val chain = peopleChain()

            getCandidateMemberRecord(chain).transformLatest { memberRecord ->
                val isInRing = memberRecord is RingPosition.Included
                if (!isInRing) {
                    emit(false)
                    return@transformLatest
                }

                emitAll(aliasExistsFlow(chain, memberRecord, context))
            }
        }.distinctUntilChanged()
    }

    override fun personhoodAccountsFullySetFlow(): Flow<Boolean> {
        return flowOfAll {
            val chain = peopleChain()

            combine(
                getPersonFlow(chain),
                getAliasesExistFlow(chain)
            ) { personRecord, aliasesExists ->
                personRecord?.account != null && aliasesExists
            }
        }
    }

    private fun getCandidateMemberRecord(chain: Chain): Flow<RingPosition?> {
        return flowOfAll {
            val account = accountRepository.getCandidateAccount()
            val personKey = bandersnatchSecretsStorage.getMemberKey(account.id)

            membersRepository.subscribePersonMember(
                chainId = chain.id,
                key = personKey,
                consistency = CacheableDataConsistency.CAN_BE_STALE,
            ).map { it.getOrNull() }
        }
    }

    private fun getPersonFlow(chain: Chain): Flow<PersonRecord?> = personIdRepository.personIdFlow().flatMapLatest {
        if (it == null) return@flatMapLatest flowOf(null)

        peopleRepository.subscribePerson(chain.id, it)
    }

    private suspend fun getAliasesExistFlow(chain: Chain): Flow<Boolean> {
        return getCandidateMemberRecord(chain).flatMapLatest { memberRecord ->
            if (memberRecord == null) return@flatMapLatest flowOf(false)

            getAliasesExistFlow(chain, memberRecord)
        }
    }

    private suspend fun getAliasesExistFlow(chain: Chain, memberRecord: RingPosition): Flow<Boolean> {
        val aliasesFlows = assignableContexts
            .map { provider ->
                accountRepository.getAliasAccount(provider.context()).accountIdIn(chain)
            }
            .map {
                peopleRepository.subscribeRegisteredAlias(chain.id, it)
            }

        return combine(aliasesFlows) { aliases ->
            val existingAliases = aliases.filterNotNull()
            val hasAllAliases = existingAliases.size == assignableContexts.size
            val allRingsMatched = existingAliases.all { it.ring == memberRecord.ringIndex }

            hasAllAliases && allRingsMatched
        }
    }

    private suspend fun aliasExistsFlow(
        chain: Chain,
        memberRecord: RingPosition,
        context: BandersnatchContext,
    ): Flow<Boolean> {
        val aliasAccountId = accountRepository.getAliasAccount(context).accountIdIn(chain)

        return peopleRepository.subscribeRegisteredAlias(chain.id, aliasAccountId).map { alias ->
            alias != null && alias.ring == memberRecord.ringIndex
        }
    }

    private suspend fun peopleChain(): Chain {
        return chainRegistry.getChain(knownChains.people)
    }
}
