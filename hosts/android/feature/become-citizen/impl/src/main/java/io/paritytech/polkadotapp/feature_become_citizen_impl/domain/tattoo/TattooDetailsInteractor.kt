package io.paritytech.polkadotapp.feature_become_citizen_impl.domain.tattoo

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.util.Modules
import io.paritytech.polkadotapp.common.utils.CoroutineDispatchers
import io.paritytech.polkadotapp.common.utils.flatMap
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.calls.commit
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.calls.proofOfInk
import io.paritytech.polkadotapp.feature_become_citizen_api.data.repository.TattooRepository
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooDetails
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooId
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.models.TattooCommitOutcome
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.repository.MobRuleRepository
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.signer.proofOfInk.ProofOfInkOriginsFactory
import io.paritytech.polkadotapp.feature_transactions.api.data.ExtrinsicService
import io.paritytech.polkadotapp.feature_transactions.api.data.isModuleError
import io.paritytech.polkadotapp.feature_transactions.api.data.isOk
import kotlinx.coroutines.withContext
import javax.inject.Inject

class TattooDetailsInteractor @Inject constructor(
    private val tattooRepository: TattooRepository,
    private val coroutineDispatchers: CoroutineDispatchers,
    private val mobRuleRepository: MobRuleRepository,
    private val chainRegistry: ChainRegistry,
    private val originsFactory: ProofOfInkOriginsFactory,
    private val extrinsicService: ExtrinsicService
) {
    suspend fun getTattooDetails(familyId: ByteArray): Result<TattooDetails> {
        return withContext(coroutineDispatchers.io) {
            runCatching {
                TattooDetails(
                    familyMetadata = tattooRepository.getTattooFamilyMetadata(familyId).getOrThrow(),
                    reviewTime = mobRuleRepository.getReviewTime()
                )
            }
        }
    }

    suspend fun commitToTattoo(tattooId: TattooId): Result<TattooCommitOutcome> {
        val chain = chainRegistry.peopleChain()

        return extrinsicService.submitExtrinsicAndAwaitExecution(chain, originsFactory.foreground.postApplyOrigin(chain)) {
            proofOfInk.commit(tattooId)
        }.mapCatching { result ->
            when {
                result.outcome.isOk() -> TattooCommitOutcome.SUCCESS
                result.outcome.isModuleError(Modules.PROOF_OF_INK, "IdUsed") -> TattooCommitOutcome.ALREADY_RESERVED
                result.outcome.isModuleError(Modules.PROOF_OF_INK, "IdReserved") -> TattooCommitOutcome.ALREADY_RESERVED
                else -> TattooCommitOutcome.UNKNOWN
            }
        }
    }

    private suspend fun MobRuleRepository.getReviewTime(): TattooDetails.ReviewTime? {
        val chainId = chainRegistry.knownChains.people

        return getMinimumReviewTime(chainId).flatMap { minimumPeriod ->
            getMaximumReviewTime(chainId).map { maximumPeriod ->
                TattooDetails.ReviewTime(minimumPeriod, maximumPeriod)
            }
        }
            .logFailure("Failed to determine review time")
            .getOrNull()
    }
}
