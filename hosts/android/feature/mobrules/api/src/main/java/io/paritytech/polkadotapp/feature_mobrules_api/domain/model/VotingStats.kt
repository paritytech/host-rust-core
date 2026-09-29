package io.paritytech.polkadotapp.feature_mobrules_api.domain.model

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainAssetWithAmount

class VotingStats(
    val totalScore: VotingPoints,
    val pendingRewards: ChainAssetWithAmount,
) {
    // For extensions
    companion object;
}

fun VotingStats.hasRewardsToClaim(): Boolean {
    return pendingRewards.amount.isPositive()
}
