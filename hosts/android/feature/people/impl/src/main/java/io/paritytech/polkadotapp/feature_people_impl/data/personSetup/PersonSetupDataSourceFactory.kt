@file:OptIn(kotlin.time.ExperimentalTime::class)

package io.paritytech.polkadotapp.feature_people_impl.data.personSetup

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchContext
import io.paritytech.polkadotapp.chains.di.RemoteSourceQualifier
import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.KnownChains
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.chains.multiNetwork.connection.ChainConnectionRefCounter
import io.paritytech.polkadotapp.chains.multiNetwork.connection.withConnectionEnabled
import io.paritytech.polkadotapp.chains.network.binding.BlockNumber
import io.paritytech.polkadotapp.chains.storage.source.StorageDataSource
import io.paritytech.polkadotapp.chains.storage.source.query.api.observeNonNull
import io.paritytech.polkadotapp.chains.storage.source.query.api.queryNonNull
import io.paritytech.polkadotapp.chains.storage.source.query.metadata
import io.paritytech.polkadotapp.chains.storage.typed.now
import io.paritytech.polkadotapp.chains.storage.typed.number
import io.paritytech.polkadotapp.chains.storage.typed.system
import io.paritytech.polkadotapp.chains.storage.typed.timestamp
import io.paritytech.polkadotapp.common.data.cache.CacheableDataConsistency
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.utils.CoroutineDispatchers
import io.paritytech.polkadotapp.common.utils.invoke
import io.paritytech.polkadotapp.common.utils.shareInBackground
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.data.repository.getCandidateAccount
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.BandersnatchSecretsStorage
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.getMemberKey
import io.paritytech.polkadotapp.feature_account_api.domain.model.MetaAccount
import io.paritytech.polkadotapp.feature_account_api.domain.model.PersonPublicKey
import io.paritytech.polkadotapp.feature_members_api.data.blockchain.calls.members
import io.paritytech.polkadotapp.feature_members_api.data.blockchain.calls.selfInclude
import io.paritytech.polkadotapp.feature_members_api.data.model.RingCollectionId
import io.paritytech.polkadotapp.feature_members_api.data.model.RingIndex
import io.paritytech.polkadotapp.feature_members_api.data.model.RingPosition
import io.paritytech.polkadotapp.feature_members_api.data.model.RingRoot
import io.paritytech.polkadotapp.feature_members_api.data.model.ringIndex
import io.paritytech.polkadotapp.feature_members_api.data.repository.MembersRepository
import io.paritytech.polkadotapp.feature_members_api.domain.SelfIncludeEligibility
import io.paritytech.polkadotapp.feature_people_api.data.model.PersonRecord
import io.paritytech.polkadotapp.feature_people_api.data.signer.origins.PeopleOrigins
import io.paritytech.polkadotapp.feature_people_api.domain.PEOPLE
import io.paritytech.polkadotapp.feature_people_api.domain.PeopleCheckMemberInRingUseCase
import io.paritytech.polkadotapp.feature_people_api.domain.PeopleCollection
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId
import io.paritytech.polkadotapp.feature_people_impl.data.model.RevisedContextualAlias
import io.paritytech.polkadotapp.feature_people_impl.data.network.blockchain.api.accountToAlias
import io.paritytech.polkadotapp.feature_people_impl.data.network.blockchain.api.keys
import io.paritytech.polkadotapp.feature_people_impl.data.network.blockchain.api.people
import io.paritytech.polkadotapp.feature_people_impl.data.network.blockchain.calls.people
import io.paritytech.polkadotapp.feature_people_impl.data.network.blockchain.calls.setPersonalAlias
import io.paritytech.polkadotapp.feature_people_impl.data.network.blockchain.calls.setPersonalIdAccount
import io.paritytech.polkadotapp.feature_people_impl.data.personSetup.PersonSetupDataSource.PeopleChainSubscriptions
import io.paritytech.polkadotapp.feature_people_impl.data.personSetup.PersonSetupDataSource.Subscriptions
import io.paritytech.polkadotapp.feature_people_impl.data.repository.getPeopleRingRoot
import io.paritytech.polkadotapp.feature_people_impl.data.repository.getPersonMember
import io.paritytech.polkadotapp.feature_transactions.api.data.ExtrinsicExecutionResult
import io.paritytech.polkadotapp.feature_transactions.api.data.ExtrinsicService
import io.paritytech.polkadotapp.feature_transactions.api.data.FormExtrinsic
import io.paritytech.polkadotapp.feature_transactions.api.domain.model.TransactionOrigin
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import javax.inject.Inject
import kotlin.coroutines.coroutineContext
import kotlin.time.Instant

interface PersonSetupDataSource {
    interface Factory {
        suspend fun <R> withDataSource(block: suspend (PersonSetupDataSource) -> R): R
    }

    val subscriptions: Deferred<Subscriptions>

    val candidateAccount: MetaAccount

    val peopleChain: Chain

    class Subscriptions(
        val people: PeopleChainSubscriptions,
    )

    class PeopleChainSubscriptions(
        val personId: Flow<PersonId?>,
        val blockNumber: Flow<BlockNumber>,
    )

    suspend fun setAlias(
        context: BandersnatchContext,
        aliasAccountId: AccountId,
    ): Result<ExtrinsicExecutionResult>

    suspend fun getRegisteredAlias(aliasAccountId: AccountId): RevisedContextualAlias?

    suspend fun getPersonRecord(personId: PersonId): PersonRecord

    suspend fun getMemberRecord(memberKey: PersonPublicKey): RingPosition?

    suspend fun getRingRoot(ringIndex: RingIndex): RingRoot

    suspend fun hasIncludedIntoRing(): Boolean

    suspend fun setPersonalIdAccount(accountId: AccountId): Result<ExtrinsicExecutionResult>

    suspend fun getCurrentEligibility(): SelfIncludeEligibility

    suspend fun submitSelfInclude(callValidAt: Instant): Result<ExtrinsicExecutionResult>
}

suspend fun PeopleChainSubscriptions.awaitPersonId(): PersonId {
    return personId.filterNotNull().first()
}

suspend fun PeopleChainSubscriptions.latestBlockNumber(): BlockNumber {
    return blockNumber.first()
}

class RealPersonSetupDataSourceFactory @Inject constructor(
    private val knownChains: KnownChains,
    private val chainRegistry: ChainRegistry,
    private val accountRepository: AccountRepository,
    private val coroutineDispatchers: CoroutineDispatchers,
    private val peopleOrigins: PeopleOrigins,
    private val chainConnectionRefCounter: ChainConnectionRefCounter,
    @RemoteSourceQualifier private val storageDataSource: StorageDataSource,
    private val extrinsicService: ExtrinsicService,
    private val bandersnatchSecretsStorage: BandersnatchSecretsStorage,
    private val membersRepository: MembersRepository,
    private val peopleCheckMemberInRingUseCase: PeopleCheckMemberInRingUseCase,
) : PersonSetupDataSource.Factory {
    override suspend fun <R> withDataSource(block: suspend (PersonSetupDataSource) -> R): R {
        val peopleChain = chainRegistry.getChain(knownChains.people)

        val account = accountRepository.getCandidateAccount()

        return chainConnectionRefCounter.withConnectionEnabled(peopleChain.id, "PersonSetupDataSource") {
            val session = RealPersonSetupDataSource(
                peopleChain = peopleChain,
                candidateAccount = account,
                coroutineScope = CoroutineScope(coroutineContext),
            )

            block(session)
        }
    }

    private inner class RealPersonSetupDataSource(
        override val peopleChain: Chain,
        override val candidateAccount: MetaAccount,
        private val coroutineScope: CoroutineScope
    ) : PersonSetupDataSource, CoroutineScope by coroutineScope {
        override val subscriptions = async(coroutineDispatchers.io) {
            initSubscriptions()
        }

        override suspend fun setAlias(
            context: BandersnatchContext,
            aliasAccountId: AccountId,
        ): Result<ExtrinsicExecutionResult> {
            return executePeopleChainTxAwaitingSuccess(
                transactionOrigin = peopleOrigins.asPersonalAliasWithProof(context = context),
            ) {
                people.setPersonalAlias(
                    aliasAccountId = aliasAccountId,
                    callValidAt = subscriptions().people.latestBlockNumber()
                )
            }
        }

        override suspend fun getRegisteredAlias(aliasAccountId: AccountId): RevisedContextualAlias? {
            return storageDataSource.query(peopleChain.id) {
                metadata.people.accountToAlias.query(aliasAccountId)
            }
        }

        override suspend fun getPersonRecord(personId: PersonId): PersonRecord {
            return storageDataSource.query(peopleChain.id) {
                metadata.people.people.queryNonNull(personId)
            }
        }

        override suspend fun getMemberRecord(memberKey: PersonPublicKey): RingPosition? {
            return membersRepository.getPersonMember(
                chainId = peopleChain.id,
                key = memberKey,
                consistency = CacheableDataConsistency.CONSISTENT_WITH_REMOTE,
            ).getOrThrow()
        }

        override suspend fun getRingRoot(ringIndex: RingIndex): RingRoot {
            return requireNotNull(
                membersRepository.getPeopleRingRoot(
                    chainId = peopleChain.id,
                    ringIndex = ringIndex,
                    consistency = CacheableDataConsistency.CONSISTENT_WITH_REMOTE,
                ).getOrThrow()
            ) { "Ring root not found for ringIndex=$ringIndex" }
        }

        override suspend fun hasIncludedIntoRing(): Boolean {
            return peopleCheckMemberInRingUseCase.checkIncludes(PeopleCollection.People).getOrDefault(false)
        }

        override suspend fun setPersonalIdAccount(accountId: AccountId): Result<ExtrinsicExecutionResult> {
            return executePeopleChainTxAwaitingSuccess(
                transactionOrigin = peopleOrigins.asPersonalIdentityWithProof()
            ) {
                people.setPersonalIdAccount(
                    personalIdAccount = accountId,
                    callValidAt = subscriptions().people.latestBlockNumber()
                )
            }
        }

        override suspend fun getCurrentEligibility(): SelfIncludeEligibility = coroutineScope {
            val collectionId = RingCollectionId.PEOPLE
            val consistency = CacheableDataConsistency.CONSISTENT_WITH_REMOTE

            val collection = membersRepository.getCollection(
                chainId = peopleChain.id,
                collectionId = collectionId,
                consistency = consistency,
            ).getOrNull()

            // Short-circuit when the chain does not configure the self-include bypass at all
            // (production). Avoids three extra storage reads per worker tick on production.
            if (collection?.selfInclusionDelay == null) {
                return@coroutineScope SelfIncludeEligibility.NotEligible
            }

            val onboardingSize = membersRepository.getOnboardingSize(
                chainId = peopleChain.id,
                collectionId = collectionId,
                consistency = consistency,
            ).getOrNull()
            if (onboardingSize == 1) {
                return@coroutineScope SelfIncludeEligibility.SelfIncludeNotNeeded
            }

            val memberKey = bandersnatchSecretsStorage.getMemberKey(candidateAccount.id)

            val positionDeferred = async {
                membersRepository.getPersonMember(
                    chainId = peopleChain.id,
                    key = memberKey,
                    consistency = consistency,
                ).getOrNull()
            }

            val ringsStateDeferred = async {
                membersRepository.getRingsState(
                    chainId = peopleChain.id,
                    collectionId = collectionId,
                    consistency = consistency,
                ).getOrNull()
            }

            val nowMsDeferred = async {
                runCatching {
                    storageDataSource.query(peopleChain.id) {
                        metadata.timestamp.now.queryNonNull()
                    }.toLong()
                }.getOrNull()
            }

            SelfIncludeEligibility.evaluate(
                position = positionDeferred.await(),
                collection = collection,
                ringsState = ringsStateDeferred.await(),
                bestBlockTime = nowMsDeferred.await()?.let(Instant::fromEpochMilliseconds),
            )
        }

        override suspend fun submitSelfInclude(callValidAt: Instant): Result<ExtrinsicExecutionResult> {
            val memberKey = bandersnatchSecretsStorage.getMemberKey(candidateAccount.id)

            return executePeopleChainTxAwaitingSuccess(
                transactionOrigin = peopleOrigins.asMember(),
            ) {
                members.selfInclude(
                    identifier = RingCollectionId.PEOPLE,
                    member = memberKey,
                    callValidAt = callValidAt.epochSeconds,
                )
            }
        }

        private suspend fun executePeopleChainTxAwaitingSuccess(
            transactionOrigin: TransactionOrigin,
            formExtrinsic: FormExtrinsic,
        ): Result<ExtrinsicExecutionResult> {
            return extrinsicService.submitExtrinsicAndAwaitExecution(
                chain = peopleChain,
                origin = transactionOrigin,
                formExtrinsic = formExtrinsic
            )
        }

        private suspend fun initSubscriptions(): Subscriptions {
            return Subscriptions(
                people = initPeopleChainSubscriptions()
            )
        }

        private suspend fun initPeopleChainSubscriptions(): PeopleChainSubscriptions {
            val memberKey = bandersnatchSecretsStorage.getMemberKey(candidateAccount.id)

            return PeopleChainSubscriptions(
                personId = storageDataSource.subscribe(peopleChain.id) {
                    metadata.people.keys.observe(memberKey)
                }.shareInBackground(),
                blockNumber = storageDataSource.subscribe(peopleChain.id) {
                    metadata.system.number.observeNonNull()
                }.shareInBackground()
            )
        }
    }
}
