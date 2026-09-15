package io.paritytech.polkadotapp.feature_mobrules_api.domain.voting

import io.paritytech.polkadotapp.feature_mobrules_api.domain.model.VotingStats
import kotlinx.coroutines.flow.Flow

interface VotingStatsUseCase {
    fun currentVotingStatsFlow(): Flow<Result<VotingStats>>
}
