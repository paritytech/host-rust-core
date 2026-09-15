package io.paritytech.polkadotapp.feature_identity_impl.domain

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchContext
import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.common.utils.combineResult
import io.paritytech.polkadotapp.common.utils.flowOfAll
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_identity_api.data.repository.UserIdentityRepository
import io.paritytech.polkadotapp.feature_identity_api.data.storage.CredentialClaimedStorage
import io.paritytech.polkadotapp.feature_identity_api.domain.CredentialPlatformsStateUseCase
import io.paritytech.polkadotapp.feature_identity_api.domain.models.*
import io.paritytech.polkadotapp.feature_identity_api.domain.models.IdentityCredentialPlatform.Companion.platformName
import io.paritytech.polkadotapp.feature_identity_api.domain.models.IdentityCredentialState.*
import io.paritytech.polkadotapp.feature_identity_impl.data.IDENTITY
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject

class RealCredentialPlatformsStateUseCase @Inject constructor(
    private val chainRegistry: ChainRegistry,
    private val accountRepository: AccountRepository,
    private val userIdentityRepository: UserIdentityRepository,
    private val credentialClaimedStorage: CredentialClaimedStorage,
) : CredentialPlatformsStateUseCase {
    override fun getIdentityCredentialStateFlow(): Flow<Result<List<IdentityCredentialConnection>>> = flowOfAll {
        val chain = chainRegistry.peopleChain()

        val identityAlias = accountRepository.getCandidateAlias(BandersnatchContext.IDENTITY)
        val identityAccount = accountRepository.getAliasAccount(BandersnatchContext.IDENTITY)

        userIdentityRepository.getPersonalIdentityFlow(chain.id, identityAlias)
            .combineResult(
                userIdentityRepository.getIdentityRegistrationFlow(chain.id, identityAccount.accountIdIn(chain))
            ) { personIdentity, identityRegistration ->
                if (personIdentity == null || identityRegistration == null) return@combineResult emptyList()

                createIdentityCredentialConnections(
                    personIdentity = personIdentity,
                    identityRegistration = identityRegistration
                )
            }
    }

    private fun createIdentityCredentialConnections(
        personIdentity: PersonalIdentity,
        identityRegistration: IdentityOf
    ): List<IdentityCredentialConnection> {
        return IdentityCredentialPlatform.platformNames().map { platformName ->
            val pendingPlatform = personIdentity.pendingJudgements.find {
                it.judgement.platformName() == platformName
            }
            val isInReview = pendingPlatform != null
            if (isInReview) {
                return@map IdentityCredentialConnection(pendingPlatform.judgement, Review)
            }
            val platform = when (platformName) {
                IdentityCredentialPlatform.TWITTER -> IdentityCredentialPlatform.Twitter(identityRegistration.info.twitter.value())
                IdentityCredentialPlatform.GITHUB -> IdentityCredentialPlatform.Github(identityRegistration.info.github.value())
                IdentityCredentialPlatform.DISCORD -> IdentityCredentialPlatform.Discord(identityRegistration.info.discord.value())
                else -> throw IllegalArgumentException("Impossible state, we're iterating over #platformNames")
            }
            val username = platform.username ?: ""
            val isRegistered = username.isNotEmpty()
            if (isRegistered) {
                return@map IdentityCredentialConnection(platform = platform, state = Confirmed(username))
            }

            val localClaimedCredential = credentialClaimedStorage.getClaimedCredentialForPlatform(platformName)
            val state = if (localClaimedCredential != null) Rejected else NotAdded
            return@map IdentityCredentialConnection(platform = platform, state = state)
        }
    }
}
