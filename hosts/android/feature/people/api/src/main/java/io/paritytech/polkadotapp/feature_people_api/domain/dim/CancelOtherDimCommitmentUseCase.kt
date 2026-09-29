package io.paritytech.polkadotapp.feature_people_api.domain.dim
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope

interface CancelOtherDimCommitmentUseCase {
    context(scope: ComputationalScope)
    suspend operator fun invoke(currentDim: DimId): Result<Unit>
}
