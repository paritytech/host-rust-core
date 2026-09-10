package io.paritytech.polkadotapp.feature_videogame_impl.domain.usecase

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import io.paritytech.polkadotapp.common.utils.flatMap
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.data.repository.getCandidateAccount
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.BandersnatchSecretsStorage
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.getMemberKey
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.sign
import io.paritytech.polkadotapp.feature_account_api.domain.model.MetaAccount
import io.paritytech.polkadotapp.feature_people_api.data.personSetup.PersonSetupStarter
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainParticipant
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainVideoGameRecognition
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.RegistrationOwnershipProof
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.ScoreRepository
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.VideoGameKeepPlayingWarningRepository
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.getAccountParticipantOrThrow
import javax.inject.Inject

interface VideoGameClaimCitizenshipUseCase {
    suspend operator fun invoke(): Result<Unit>
}

class RealVideoGameClaimCitizenshipUseCase @Inject constructor(
    private val scoreRepository: ScoreRepository,
    private val accountRepository: AccountRepository,
    private val chainRegistry: ChainRegistry,
    private val bandersnatchSecretsStorage: BandersnatchSecretsStorage,
    private val personSetupStarter: PersonSetupStarter,
    private val gamesWarningRepository: VideoGameKeepPlayingWarningRepository,
) : VideoGameClaimCitizenshipUseCase {
    override suspend operator fun invoke(): Result<Unit> {
        val chain = chainRegistry.peopleChain()

        // Reset the previous person setup progress as we will start from scratch after claiming personhood
        personSetupStarter.resetProgress()
        // Even if it is the second user onboarding, we want to show them warning again
        // As they have missed some game in the past
        gamesWarningRepository.resetWarningAcknowledgment()

        return prepareOwnershipProof(chain)
            .flatMap { scoreRepository.register(chain, it) }
    }

    private suspend fun prepareOwnershipProof(chain: Chain): Result<RegistrationOwnershipProof?> {
        return runCatching {
            val account = accountRepository.getCandidateAccount()
            val accountId = account.accountIdIn(chain)

            val scoreState = scoreRepository.getAccountParticipantOrThrow(chain.id, accountId)
            generateFirstTimeOwnershipProof(chain, account, scoreState)
        }
    }

    private suspend fun generateFirstTimeOwnershipProof(
        chain: Chain,
        account: MetaAccount,
        scoreParticipant: OnChainParticipant,
    ): RegistrationOwnershipProof? {
        return when (scoreParticipant.recognition) {
            OnChainVideoGameRecognition.NotRecognized -> generateOwnershipProof(chain, account)

            // Registering personhood from suspended state means user has already been a person before
            // So there is no need to submit a proof second time
            is OnChainVideoGameRecognition.Suspended -> null

            is OnChainVideoGameRecognition.Recognized,
            is OnChainVideoGameRecognition.ExternallyRecognized -> error("Personhood is already recognized")
        }
    }

    private suspend fun generateOwnershipProof(
        chain: Chain,
        account: MetaAccount
    ): RegistrationOwnershipProof {
        val accountId = account.accountIdIn(chain)
        val ownershipMessage = scoreRepository.generateProofOfOwnershipMessage(accountId)
        val ownershipProof = bandersnatchSecretsStorage.sign(account.id, ownershipMessage)
        val memberKey = bandersnatchSecretsStorage.getMemberKey(account.id)

        return RegistrationOwnershipProof(memberKey, ownershipProof.toDataByteArray())
    }
}
