package io.paritytech.polkadotapp.feature_become_citizen_impl.domain.family.list

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.common.utils.getOrEmpty
import io.paritytech.polkadotapp.common.utils.requireNotNull
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.data.repository.getCandidateAccount
import io.paritytech.polkadotapp.feature_become_citizen_api.data.repository.TattooRepository
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.candidateState.TattooProgressStateUseCase
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.DesignedTattooFlatId
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooFamily
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooFamilyIndex
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooFamilyKind
import io.paritytech.polkadotapp.feature_people_api.data.repository.PersonIdRepository
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.withContext
import javax.inject.Inject

interface TattooFamilyDetailsInteractor {
    suspend fun getCollection(index: TattooFamilyIndex): Result<TattooCollection>
    suspend fun getCollections(indexes: List<TattooFamilyIndex>): Result<List<TattooCollection>>
}

class RealTattooFamilyDetailsInteractor @Inject constructor(
    private val tattooRepository: TattooRepository,
    private val accountRepository: AccountRepository,
    private val personIdRepository: PersonIdRepository,
    private val chainRegistry: ChainRegistry,
    private val tattooProgressStateUseCase: TattooProgressStateUseCase
) : TattooFamilyDetailsInteractor {
    override suspend fun getCollection(index: TattooFamilyIndex): Result<TattooCollection> =
        withContext(Dispatchers.IO) {
            val peopleChain = chainRegistry.peopleChain()
            val committedTattoos = async { tattooRepository.getAllCommittedTattoos(peopleChain.id).getOrEmpty() }

            tattooRepository.getDesignFamily(peopleChain.id, index)
                .requireNotNull()
                .map { family ->
                    createTattooCollection(family, committedTattoos, peopleChain)
                }
        }

    override suspend fun getCollections(indexes: List<TattooFamilyIndex>): Result<List<TattooCollection>> =
        withContext(Dispatchers.IO) {
            val peopleChain = chainRegistry.peopleChain()

            tattooRepository.getDesignFamilies(peopleChain.id, indexes)
                .map { list ->
                    val committedTattoos = async { tattooRepository.getAllCommittedTattoos(peopleChain.id).getOrEmpty() }

                    list.map { family ->
                        createTattooCollection(family, committedTattoos, peopleChain)
                    }
                }
        }

    private suspend fun createTattooCollection(
        family: TattooFamily,
        committedTattoos: Deferred<Set<DesignedTattooFlatId>>,
        chain: Chain
    ): TattooCollection {
        val metadata = tattooRepository.getTattooFamilyMetadata(family.id).getOrThrow()

        return when (val kind = family.kind) {
            is TattooFamilyKind.Designed -> TattooCollection.createDesigned(
                familyId = family.id,
                kind = kind,
                metadata = metadata,
                alreadyTakenTattoos = committedTattoos.await()
            )

            is TattooFamilyKind.Procedural -> TattooCollection.createProcedural(
                familyId = family.id,
                kind = kind,
                metadata = metadata,
                entropy = this@RealTattooFamilyDetailsInteractor.tattooProgressStateUseCase.getProceduralTattooEntropyForCurrentState().getOrThrow()
            )

            is TattooFamilyKind.ProceduralAccount -> TattooCollection.createProceduralAccount(
                familyId = family.id,
                kind = kind,
                metadata = metadata,
                accountId = accountRepository.getCandidateAccount().accountIdIn(chain)
            )

            is TattooFamilyKind.ProceduralPersonal -> TattooCollection.createProceduralPersonal(
                familyId = family.id,
                kind = kind,
                metadata = metadata,
                personId = personIdRepository.getNextAvailablePersonId(chain.id).getOrThrow()
            )
        }
    }
}
