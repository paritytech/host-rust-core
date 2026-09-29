package io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.model

import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.model.VoteCaseContext
import io.paritytech.polkadotapp.feature_mobrules_impl.domain.voting.model.MobRuleVote
import io.paritytech.polkadotapp.common.R as RCommon

fun VotingCaseUiModel.toVoteCaseContext(): VoteCaseContext =
    when (this) {
        is VotingCaseUiModel.Photo -> VoteCaseContext.Photo(
            caseId = id,
            evidenceHash = proofImage.contentHash.toDataByteArray(),
            tattooId = tattooId,
            tattooFamilyId = tattooFamilyId
        )
        is VotingCaseUiModel.Video -> VoteCaseContext.Video(
            caseId = id,
            evidenceHash = evidenceHash,
            tattooId = tattooId,
            tattooFamilyId = tattooFamilyId
        )
        is VotingCaseUiModel.Credentials,
        is VotingCaseUiModel.UsernameValid -> error("Not yet supported")
    }

fun MobRuleVote.toVoteStringRes(): Int {
    return when (this) {
        is MobRuleVote.Truth -> when (opinion) {
            MobRuleVote.TruthOpinion.True -> RCommon.string.mob_rule_vote_true
            MobRuleVote.TruthOpinion.False -> RCommon.string.mob_rule_vote_false
        }
        MobRuleVote.Contempt -> RCommon.string.mob_rule_vote_false
    }
}
