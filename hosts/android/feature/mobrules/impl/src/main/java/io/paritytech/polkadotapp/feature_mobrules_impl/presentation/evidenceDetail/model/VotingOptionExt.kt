package io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.model

import io.paritytech.polkadotapp.feature_mobrules_impl.domain.voting.model.MobRuleVote

fun VotingOption.toMobRuleVote(): MobRuleVote {
    val opinion = when (this) {
        VotingOption.TRUE -> MobRuleVote.TruthOpinion.True
        VotingOption.FALSE -> MobRuleVote.TruthOpinion.False
    }
    return MobRuleVote.Truth(opinion)
}
