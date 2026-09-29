package io.paritytech.polkadotapp.feature_become_citizen_impl.domain.candidateState

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.common.utils.coerceToUnit
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.calls.apply
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.calls.proofOfInk
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.candidateState.CitizenshipApplyUseCase
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.signer.proofOfInk.ProofOfInkOriginsFactory
import io.paritytech.polkadotapp.feature_transactions.api.data.ExtrinsicService
import io.paritytech.polkadotapp.feature_transactions.api.data.flattenExecutionFailure
import timber.log.Timber
import javax.inject.Inject

class RealCitizenshipApplyUseCase @Inject constructor(
    private val extrinsicService: ExtrinsicService,
    private val chainRegistry: ChainRegistry,
    private val proofOfInkOriginsFactory: ProofOfInkOriginsFactory
) : CitizenshipApplyUseCase {
    override suspend fun applyCitizenship(): Result<Unit> {
        val origin = proofOfInkOriginsFactory.foreground.applyWithDepositOrigin()
        return extrinsicService.submitExtrinsicAndAwaitExecution(
            chain = chainRegistry.peopleChain(),
            origin = origin
        ) {
            proofOfInk.apply()
        }.flattenExecutionFailure()
            .onFailure { Timber.d(it, "Failed to apply to proof of ink") }
            .coerceToUnit()
    }
}
