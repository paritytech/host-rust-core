package io.paritytech.polkadotapp.feature_identity_impl.data.repository

import io.novasama.substrate_sdk_android.encrypt.SignatureWrapper
import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchContext
import io.paritytech.polkadotapp.chains.di.LocalSourceQualifier
import io.paritytech.polkadotapp.chains.di.RemoteSourceQualifier
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.chains.storage.source.*
import io.paritytech.polkadotapp.chains.storage.source.query.metadata
import io.paritytech.polkadotapp.chains.util.sign
import io.paritytech.polkadotapp.chains.util.signing.MessageSigningContext
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.utils.flatMap
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.AccountSecretsStorage
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.getMetaAccountSr25519Keypair
import io.paritytech.polkadotapp.feature_account_api.domain.model.MetaAccount
import io.paritytech.polkadotapp.feature_identity_api.data.repository.UserIdentityRepository
import io.paritytech.polkadotapp.feature_identity_api.data.storage.ClaimedUsernameStorage
import io.paritytech.polkadotapp.feature_identity_api.domain.models.*
import io.paritytech.polkadotapp.feature_identity_impl.data.IDENTITY
import io.paritytech.polkadotapp.feature_identity_impl.data.network.blockchain.*
import io.paritytech.polkadotapp.feature_people_api.data.signer.origins.PeopleOrigins
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonalAlias
import io.paritytech.polkadotapp.feature_transactions.api.data.*
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject

class RealUserIdentityRepository @Inject constructor(
    private val extrinsicService: ExtrinsicService,
    private val accountSecretsStorage: AccountSecretsStorage,
    private val claimedUsernameStorage: ClaimedUsernameStorage,
    @RemoteSourceQualifier private val remoteStorageDataSource: StorageDataSource,
    @LocalSourceQualifier private val localStorageDataSource: StorageDataSource,
    private val peopleOrigins: PeopleOrigins
) : UserIdentityRepository {
    override suspend fun setPersonalIdentity(chain: Chain, identityAccount: MetaAccount, identityAlias: PersonalAlias, username: String): Result<Unit> {
        return peopleOrigins.asPersonalAliasWithAccountEnsuringRevision(BandersnatchContext.IDENTITY).flatMap { origin ->
            extrinsicService.submitExtrinsicAndAwaitExecution(
                chain = chain,
                origin = origin
            ) {
                val signature = accountSecretsStorage.getMetaAccountSr25519Keypair(identityAccount.id)
                    .sign(identityAlias.value, MessageSigningContext.trustedContent())

                identity.setPersonalIdentity(
                    accountId = identityAccount.accountIdIn(chain),
                    signatureWrapper = SignatureWrapper.Sr25519(signature),
                    username = username.encodeToByteArray()
                )
            }.mapCatching { result ->
                result.requireOk()

                claimedUsernameStorage.setClaimedUsername(username)
            }
        }
    }

    override suspend fun getClaimedUsername(): String {
        return claimedUsernameStorage.getClaimedUsername()
    }

    override fun getClaimedUsernameFlow(): Flow<String?> {
        return claimedUsernameStorage.getClaimedUsernameFlow()
    }

    override suspend fun saveClaimedUsername(username: String) {
        claimedUsernameStorage.setClaimedUsername(username)
    }

    override suspend fun getUsernameInfo(chainId: ChainId, username: String): Result<AccountId?> {
        return remoteStorageDataSource.queryCatching(chainId) {
            metadata.identity.usernameInfoOf.query(username.encodeToByteArray())?.owner
        }
    }

    override suspend fun getUsernameOf(chainId: ChainId, accountId: AccountId): Result<String?> {
        return remoteStorageDataSource.queryCatching(chainId) {
            metadata.identity.usernameOf.query(accountId.value)
        }
    }

    override fun getPersonalIdentityFlow(chainId: ChainId, identityAlias: PersonalAlias): Flow<Result<PersonalIdentity?>> {
        return localStorageDataSource.subscribeCatching(chainId) {
            metadata.identity.personIdentities.observe(identityAlias)
        }
    }

    override fun getIdentityRegistrationFlow(chainId: ChainId, accountId: AccountId): Flow<Result<IdentityOf?>> {
        return localStorageDataSource.subscribeCatching(chainId) {
            metadata.identity.identityOf.observe(accountId)
        }
    }

    override suspend fun submitCredentials(
        chain: Chain,
        platform: IdentityCredentialPlatform,
        credential: String
    ): Result<ExtrinsicExecutionResult> {
        return peopleOrigins.asPersonalAliasWithAccountEnsuringRevision(BandersnatchContext.IDENTITY).flatMap { transactionOrigin ->
            extrinsicService.submitExtrinsicAndAwaitExecution(
                chain = chain,
                origin = transactionOrigin
            ) {
                identity.submitPersonalCredentialEvidence(platform, credential)
            }
        }
    }
}
