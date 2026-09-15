package io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.model

import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooIdCustomContent
import kotlinx.serialization.Serializable

@Serializable
data class MobRuleVotedCaseContent(
    val caseId: String,
    val caseType: CaseType,
    val evidenceHashHex: String?,
    val tattooId: TattooIdCustomContent,
    val tattooFamilyIdHex: String
)
