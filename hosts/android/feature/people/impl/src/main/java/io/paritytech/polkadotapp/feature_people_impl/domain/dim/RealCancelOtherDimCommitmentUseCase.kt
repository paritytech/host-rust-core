package io.paritytech.polkadotapp.feature_people_impl.domain.dim

import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.feature_people_api.domain.dim.CancelOtherDimCommitmentUseCase
import io.paritytech.polkadotapp.feature_people_api.domain.dim.DimCommitmentHandler
import io.paritytech.polkadotapp.feature_people_api.domain.dim.DimId
import javax.inject.Inject

class RealCancelOtherDimCommitmentUseCase @Inject constructor(
    private val handlers: Set<@JvmSuppressWildcards DimCommitmentHandler>
) : CancelOtherDimCommitmentUseCase {
    context(scope: ComputationalScope)
    override suspend fun invoke(currentDim: DimId): Result<Unit> {
        val otherCanceller = handlers.find { it.dimId != currentDim }
            ?: return Result.failure(IllegalStateException("No other DIMs (non $currentDim) found for cancellation."))

        return otherCanceller.cancel()
    }
}
