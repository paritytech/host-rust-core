package io.paritytech.polkadotapp.feature_become_citizen_impl.domain.family.list

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.withAmount
import io.paritytech.polkadotapp.chains.util.planksFromAmount
import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.common.utils.filterResultSuccess
import io.paritytech.polkadotapp.common.utils.flowOfAll
import io.paritytech.polkadotapp.common.utils.forEachAsync
import io.paritytech.polkadotapp.common.utils.getOrEmpty
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.data.repository.getCandidateAccount
import io.paritytech.polkadotapp.feature_balances_api.data.repository.BalanceRepository
import io.paritytech.polkadotapp.feature_become_citizen_api.data.repository.TattooRepository
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.CandidateDepositAssetProvider
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.TattooProgressState
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.candidateState.CitizenshipApplyUseCase
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.candidateState.TattooProgressStateUseCase
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.DesignedTattooFlatId
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooFamily
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooFamilyKind
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.family.model.CandidateApplicableState
import io.paritytech.polkadotapp.feature_people_api.data.repository.PersonIdRepository
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId
import io.paritytech.polkadotapp.feature_tokens_api.domain.ChainAssetProvider
import io.paritytech.polkadotapp.feature_transfers_api.domain.usecase.TestnetFundUseCase
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.withContext
import timber.log.Timber
import java.math.BigDecimal
import javax.inject.Inject

interface TattooFamilyListInteractor {
    fun getTattooCollections(): Flow<List<TattooCollection>>
    fun subscribeApplicableState(): Flow<CandidateApplicableState>
    suspend fun apply(): Result<Unit>
    suspend fun deposit(amount: BigDecimal): Result<Unit>
}

class RealTattooFamilyListInteractor @Inject constructor(
    private val tattooRepository: TattooRepository,
    private val accountRepository: AccountRepository,
    private val tattooProgressStateUseCase: TattooProgressStateUseCase,
    @param:CandidateDepositAssetProvider private val chatAssetProvider: ChainAssetProvider,
    private val personIdRepository: PersonIdRepository,
    private val balanceRepository: BalanceRepository,
    private val citizenshipApplyUseCase: CitizenshipApplyUseCase,
    private val testnetFundUseCase: TestnetFundUseCase
) : TattooFamilyListInteractor {
    override fun getTattooCollections() = channelFlow {
        withContext(Dispatchers.IO) {
            val chain = chatAssetProvider.chain()

            val commitedTattoos = tattooRepository.getAllCommittedTattoos(chain.id)
                .onFailure { Timber.e(it, "Failed to get committed tattoos") }
                .getOrEmpty()

            val proceduralTattoosEntropy = tattooProgressStateUseCase.getProceduralTattooEntropyForCurrentState()
                .onFailure { Timber.e(it, "Failed to get tattoos entropy") }
                .getOrNull()

            val nextAvailablePersonId = personIdRepository.getNextAvailablePersonId(chain.id)
                .onFailure { Timber.e(it, "Failed to get next available person id") }
                .getOrNull()

            val designFamilies = tattooRepository.getAllDesignFamilies(chain.id).getOrEmpty()

            designFamilies.forEachAsync { tattooFamily ->
                val collection = fetchTattooFamilyCollection(
                    chain = chain,
                    family = tattooFamily,
                    commitedTattoos = commitedTattoos,
                    proceduralTattoosEntropy = proceduralTattoosEntropy,
                    nextAvailablePersonId = nextAvailablePersonId
                )
                if (collection != null) {
                    send(collection)
                } else {
                    Timber.e("Failed to get tattoo collection ${tattooFamily.kind.familyIndex} (${tattooFamily.kind::class.simpleName})")
                }
            }
        }
    }.runningFold(emptyList<TattooCollection>()) { acc, item ->
        buildList {
            addAll(acc)
            add(item)
        }
    }

    suspend fun fetchTattooFamilyCollection(
        chain: Chain,
        family: TattooFamily,
        commitedTattoos: Set<DesignedTattooFlatId>,
        proceduralTattoosEntropy: DataByteArray?,
        nextAvailablePersonId: PersonId?
    ): TattooCollection? {
        val metadata = tattooRepository.getTattooFamilyMetadata(family.id)
            .logFailure("Failed to  fetch metadata for family ${family.kind.familyIndex} (${family.kind::class.simpleName})")
            .getOrNull() ?: return null

        return when (val kind = family.kind) {
            is TattooFamilyKind.Designed -> TattooCollection.createDesigned(
                familyId = family.id,
                kind = kind,
                metadata = metadata,
                alreadyTakenTattoos = commitedTattoos
            )

            is TattooFamilyKind.Procedural -> TattooCollection.createProcedural(
                familyId = family.id,
                kind = kind,
                metadata = metadata,
                entropy = proceduralTattoosEntropy ?: return null
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
                personId = nextAvailablePersonId ?: return null
            )
        }
    }

    override fun subscribeApplicableState(): Flow<CandidateApplicableState> = flowOfAll {
        val account = accountRepository.getCandidateAccount()

        val chain = chatAssetProvider.chain()
        val asset = chatAssetProvider.asset()

        combine(
            tattooProgressStateUseCase.tattooProgressStateFlow().filterResultSuccess(),
            balanceRepository.syncedTokenBalanceFlow(account.id, asset)
        ) { candidateState, currentBalance ->
            when (candidateState) {
                is TattooProgressState.Applied -> CandidateApplicableState.Applied
                is TattooProgressState.NotStarted -> {
                    val applyDeposit = tattooRepository.getApplyDeposit(chain)

                    if (currentBalance.canReserve(applyDeposit)) {
                        val tokenAmount = asset.withAmount(currentBalance.free)
                        CandidateApplicableState.CanApply(tokenAmount)
                    } else {
                        val tokenAmount = asset.withAmount(applyDeposit)
                        CandidateApplicableState.NotEnoughBalance(tokenAmount)
                    }
                }

                else -> {
                    Timber.w("Candidate state is unexpected for tattoo selection flow: ${candidateState?.let { it::class.simpleName }}")
                    CandidateApplicableState.Unexpected
                }
            }
        }
    }.distinctUntilChanged()

    override suspend fun apply(): Result<Unit> = citizenshipApplyUseCase.applyCitizenship()

    override suspend fun deposit(amount: BigDecimal): Result<Unit> {
        val chainWithAsset = chatAssetProvider()
        return testnetFundUseCase(
            amount = amount.planksFromAmount(chainWithAsset.asset.precision),
            chainWithAsset = chainWithAsset,
            to = accountRepository.getCandidateAccount().accountIdIn(chainWithAsset.chain)
        )
    }
}
