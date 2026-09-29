package io.paritytech.polkadotapp.feature_people_api.domain.dim

import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import kotlinx.coroutines.flow.Flow

interface GetActiveDimCommitmentState {
    context(scope: ComputationalScope)
    operator fun invoke(currentDim: DimId): Flow<DimState?>
}
