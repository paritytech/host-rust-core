package io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.model

import androidx.compose.runtime.Immutable
import kotlinx.serialization.Serializable

@Immutable
@Serializable
data class MobRuleCaseStatusContent(
    val caseId: String,
    val status: CaseJudgmentStatus,
    val userVoteType: UserVoteType,
)

@Serializable
enum class CaseJudgmentStatus { PROCESSING, CORRECT, INCORRECT }

@Serializable
enum class UserVoteType { TRUE, FALSE }
