package io.paritytech.polkadotapp.feature_mobrules_impl.domain.voting

import io.paritytech.polkadotapp.feature_mobrules_impl.domain.voting.model.MobRuleVote
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.model.UserVoteType

fun UserVoteType.matchesVerdict(verdict: MobRuleVote.Truth): Boolean {
    return when (verdict.opinion) {
        MobRuleVote.TruthOpinion.True -> this == UserVoteType.TRUE
        MobRuleVote.TruthOpinion.False -> this == UserVoteType.FALSE
    }
}
