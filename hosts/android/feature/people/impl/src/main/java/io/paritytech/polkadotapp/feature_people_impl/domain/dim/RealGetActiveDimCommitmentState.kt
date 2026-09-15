package io.paritytech.polkadotapp.feature_people_impl.domain.dim

import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.feature_people_api.domain.dim.DimCommitmentHandler
import io.paritytech.polkadotapp.feature_people_api.domain.dim.DimId
import io.paritytech.polkadotapp.feature_people_api.domain.dim.DimState
import io.paritytech.polkadotapp.feature_people_api.domain.dim.GetActiveDimCommitmentState
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flowOf
import javax.inject.Inject

class RealGetActiveDimCommitmentState @Inject constructor(
    private val handlers: Set<@JvmSuppressWildcards DimCommitmentHandler>
) : GetActiveDimCommitmentState {
    context(scope: ComputationalScope)
    override fun invoke(currentDim: DimId): Flow<DimState?> {
        val otherHandlers = handlers.filter { it.dimId != currentDim }

        if (otherHandlers.isEmpty()) {
            return flowOf(null)
        }

        val stateFlows = otherHandlers.map { it.observeState() }

        return combine(stateFlows) { states ->
            states.firstOrNull { it is DimState.Started }
        }
    }
}
