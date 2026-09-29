package io.paritytech.polkadotapp.feature_identity_api.data.repository

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_account_api.domain.model.MetaAccount
import io.paritytech.polkadotapp.feature_identity_api.domain.models.*
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonalAlias
import io.paritytech.polkadotapp.feature_transactions.api.data.ExtrinsicExecutionResult
import kotlinx.coroutines.flow.Flow

interface UserIdentityRepository {
    suspend fun setPersonalIdentity(chain: Chain, identityAccount: MetaAccount, identityAlias: PersonalAlias, username: String): Result<Unit>
    suspend fun getClaimedUsername(): String
    fun getClaimedUsernameFlow(): Flow<String?>
    suspend fun saveClaimedUsername(username: String)

    suspend fun getUsernameInfo(chainId: ChainId, username: String): Result<AccountId?>
    suspend fun getUsernameOf(chainId: ChainId, accountId: AccountId): Result<String?>

    fun getPersonalIdentityFlow(chainId: ChainId, identityAlias: PersonalAlias): Flow<Result<PersonalIdentity?>>
    fun getIdentityRegistrationFlow(chainId: ChainId, accountId: AccountId): Flow<Result<IdentityOf?>>

    suspend fun submitCredentials(
        chain: Chain,
        platform: IdentityCredentialPlatform,
        credential: String
    ): Result<ExtrinsicExecutionResult>
}
