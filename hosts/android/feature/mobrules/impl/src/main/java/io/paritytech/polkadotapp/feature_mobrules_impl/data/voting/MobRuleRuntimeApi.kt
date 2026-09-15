package io.paritytech.polkadotapp.feature_mobrules_impl.data.voting

import io.novasama.substrate_sdk_android.koltinx_serialization_scale.Scale
import io.novasama.substrate_sdk_android.koltinx_serialization_scale.decode
import io.paritytech.polkadotapp.chains.call.RuntimeCallsApi
import io.paritytech.polkadotapp.chains.util.scaleEncodeSerializable
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.model.MobRuleCaseId
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonalAlias

class MobRuleRuntimeCallsApi(val api: RuntimeCallsApi)

val RuntimeCallsApi.mobRule: MobRuleRuntimeCallsApi
    get() = MobRuleRuntimeCallsApi(this)

suspend fun MobRuleRuntimeCallsApi.votedOn(voter: PersonalAlias, doneOnly: Boolean): List<MobRuleCaseId> {
    return api.call(
        section = "MobRuleApi",
        method = "voted_on",
        arguments = mapOf(
            "voter" to voter.scaleEncodeSerializable(),
            "done_only" to doneOnly.scaleEncodeSerializable()
        ),
        returnBinding = { Scale.decode(it) }
    )
}
