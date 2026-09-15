package io.paritytech.polkadotapp.feature_mobrules_impl.domain.voting.model

import io.novasama.substrate_sdk_android.koltinx_serialization_scale.annotations.TransientStruct
import kotlinx.serialization.Serializable

@Serializable
sealed class MobRuleVote {
    @Serializable
    data object Contempt : MobRuleVote()

    @Serializable
    @TransientStruct
    class Truth(val opinion: TruthOpinion) : MobRuleVote()

    @Serializable
    sealed class TruthOpinion {
        @Serializable
        data object True : TruthOpinion()

        @Serializable
        data object False : TruthOpinion()
    }
}
