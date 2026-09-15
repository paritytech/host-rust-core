package io.paritytech.polkadotapp.feature_people_impl.data.signer.origins

import io.novasama.substrate_sdk_android.extensions.toHexString
import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchContext
import io.paritytech.polkadotapp.chains.di.RemoteSourceQualifier
import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.KnownChains
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.chains.network.binding.BlockNumber
import io.paritytech.polkadotapp.chains.repository.ChainStateRepository
import io.paritytech.polkadotapp.chains.storage.source.StorageDataSource
import io.paritytech.polkadotapp.chains.storage.source.query.StorageQueryContext
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.utils.coerceToUnit
import io.paritytech.polkadotapp.common.utils.flatMap
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.data.repository.getCandidateAccount
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.BandersnatchSecretsStorage
import io.paritytech.polkadotapp.feature_members_api.data.repository.MembersRepository
import io.paritytech.polkadotapp.feature_people_api.data.repository.PersonIdRepository
import io.paritytech.polkadotapp.feature_people_api.data.repository.getPersonIdOrThrow
import io.paritytech.polkadotapp.feature_people_api.data.signer.origins.PeopleOrigins
import io.paritytech.polkadotapp.feature_people_api.domain.PeopleMembershipProver
import io.paritytech.polkadotapp.feature_people_impl.data.network.blockchain.calls.people
import io.paritytech.polkadotapp.feature_people_impl.data.network.blockchain.calls.setPersonalAlias
import io.paritytech.polkadotapp.feature_people_impl.data.signer.origins.datasource.StoragePeopleOriginsDataSource
import io.paritytech.polkadotapp.feature_people_impl.data.signer.origins.extension.AsMemberTransactionExtension
import io.paritytech.polkadotapp.feature_people_impl.data.signer.origins.extension.AsPersonalAliasWithAccount
import io.paritytech.polkadotapp.feature_people_impl.data.signer.origins.extension.AsPersonalAliasWithProof
import io.paritytech.polkadotapp.feature_people_impl.data.signer.origins.extension.AsPersonalIdentityWithAccount
import io.paritytech.polkadotapp.feature_people_impl.data.signer.origins.extension.AsPersonalIdentityWithProof
import io.paritytech.polkadotapp.feature_transactions.api.data.ExtrinsicService
import io.paritytech.polkadotapp.feature_transactions.api.data.flattenExecutionFailure
import io.paritytech.polkadotapp.feature_transactions.api.domain.model.SetTransactionExtensionOrigin
import io.paritytech.polkadotapp.feature_transactions.api.domain.model.TransactionOrigin
import io.paritytech.polkadotapp.feature_transactions.api.domain.model.TransactionSignerSource
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class RealPeopleOrigins @Inject constructor(
    private val accountRepository: AccountRepository,
    private val personIdRepository: PersonIdRepository,
    private val bandersnatchSecretsStorage: BandersnatchSecretsStorage,
    private val extrinsicService: ExtrinsicService,
    @RemoteSourceQualifier private val storageDataSource: StorageDataSource,
    private val chainStateRepository: ChainStateRepository,
    private val chainRegistry: ChainRegistry,
    private val knownChains: KnownChains,
    private val membersRepository: MembersRepository,
    private val peopleMembershipProver: PeopleMembershipProver,
) : PeopleOrigins {
    private val peopleOriginsDataSource = object : StoragePeopleOriginsDataSource(membersRepository) {
        override val extrinsicService: ExtrinsicService = this@RealPeopleOrigins.extrinsicService

        override suspend fun <R> query(chainId: ChainId, query: suspend StorageQueryContext.() -> R): R {
            return storageDataSource.query(chainId, query = query)
        }

        override suspend fun currentBlockNumber(chainId: ChainId): BlockNumber {
            return chainStateRepository.currentBlock(chainId)
        }
    }

    override suspend fun asPersonalAliasWithAccountEnsuringRevision(context: BandersnatchContext): Result<TransactionOrigin> {
        val aliasAccount = accountRepository.getAliasAccount(context)
        val chain = chainRegistry.getChain(knownChains.people)
        val accountId = aliasAccount.accountIdIn(chain)

        return maybeUpdateAlias(chain, accountId, context).map {
            val asPersonExtension = AsPersonalAliasWithAccount()
            SetTransactionExtensionOrigin(TransactionSignerSource.FromAccount(aliasAccount), asPersonExtension)
        }
    }

    override suspend fun asPersonalAliasWithAccountCreatingAlias(context: BandersnatchContext): Result<TransactionOrigin> {
        // TODO: implement creating an alias using transaction extension instead of separate transaction
        return asPersonalAliasWithAccountEnsuringRevision(context)
    }

    override suspend fun asPersonalAliasWithProof(
        context: BandersnatchContext,
    ): TransactionOrigin {
        val asPersonExtension = AsPersonalAliasWithProof(
            context = context,
            peopleMembershipProver = peopleMembershipProver,
            chainRegistry = chainRegistry,
        )

        return SetTransactionExtensionOrigin(TransactionSignerSource.None, asPersonExtension)
    }

    override suspend fun asPersonalIdentityWithProof(): TransactionOrigin {
        val candidateAccount = accountRepository.getCandidateAccount()

        val asPersonExtension = AsPersonalIdentityWithProof(
            personIdRepository = personIdRepository,
            bandersnatchSecretsStorage = bandersnatchSecretsStorage,
            candidateMetaId = candidateAccount.id
        )

        return SetTransactionExtensionOrigin(TransactionSignerSource.None, asPersonExtension)
    }

    override suspend fun asPersonalIdentityWithAccount(): TransactionOrigin {
        val candidateAccount = accountRepository.getCandidateAccount()

        val asIdentityExtension = AsPersonalIdentityWithAccount()

        return SetTransactionExtensionOrigin(TransactionSignerSource.FromAccount(candidateAccount), asIdentityExtension)
    }

    override suspend fun asMember(): TransactionOrigin {
        val candidateAccount = accountRepository.getCandidateAccount()

        val asMemberExtension = AsMemberTransactionExtension(
            candidateMetaId = candidateAccount.id,
            bandersnatchSecretsStorage = bandersnatchSecretsStorage,
        )

        return SetTransactionExtensionOrigin(
            signerSource = TransactionSignerSource.None,
            transactionExtension = asMemberExtension,
        )
    }

    private suspend fun maybeUpdateAlias(
        chain: Chain,
        aliasAccountId: AccountId,
        context: BandersnatchContext
    ): Result<Unit> {
        return runCatching {
            peopleOriginsDataSource.isAliasUpToDate(
                chainId = chain.id,
                aliasAccountId = aliasAccountId,
                personId = personIdRepository.getPersonIdOrThrow()
            )
        }.flatMap { isUpToDate ->
            if (isUpToDate) {
                Timber.d("Alias for ${context.stringValue} is up to date. Nothing to update")

                return Result.success(Unit)
            }

            Timber.d("Alias for ${context.stringValue} is outdated. Updating the revision")

            extrinsicService.submitExtrinsicAndAwaitExecution(
                chain = chain,
                origin = asPersonalAliasWithProof(context)
            ) {
                people.setPersonalAlias(
                    aliasAccountId = aliasAccountId,
                    callValidAt = peopleOriginsDataSource.currentBlockNumber(chain.id)
                )
            }
                .flattenExecutionFailure()
                .coerceToUnit()
                .onSuccess { Timber.d("Alias for ${context.stringValue} is successfully updated") }
        }.logFailure("Failed to ensure correct revision of an alias: ${context.stringValue} ${aliasAccountId.value.toHexString()}")
    }
}
