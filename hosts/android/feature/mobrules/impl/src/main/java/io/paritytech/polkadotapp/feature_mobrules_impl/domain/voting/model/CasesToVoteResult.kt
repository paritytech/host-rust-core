package io.paritytech.polkadotapp.feature_mobrules_impl.domain.voting.model

data class CasesToVoteResult(
    val cases: List<MobRuleCase>,
    val hasEverVotedOnChain: Boolean
)
