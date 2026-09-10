package io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.model

import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooId

sealed interface VoteCaseContext {
    val caseId: MobRuleCaseId

    data class Photo(
        override val caseId: MobRuleCaseId,
        val evidenceHash: DataByteArray?,
        val tattooId: TattooId,
        val tattooFamilyId: DataByteArray
    ) : VoteCaseContext

    data class Video(
        override val caseId: MobRuleCaseId,
        val evidenceHash: DataByteArray?,
        val tattooId: TattooId,
        val tattooFamilyId: DataByteArray
    ) : VoteCaseContext
}
