package io.paritytech.polkadotapp.feature_people_impl.data.network.blockchain.calls

import io.novasama.substrate_sdk_android.runtime.extrinsic.builder.ExtrinsicBuilder
import io.novasama.substrate_sdk_android.runtime.extrinsic.call
import io.paritytech.polkadotapp.chains.network.binding.BlockNumber
import io.paritytech.polkadotapp.chains.util.Modules
import io.paritytech.polkadotapp.common.domain.model.AccountId

@JvmInline
value class PeopleCalls(val extrinsicBuilder: ExtrinsicBuilder)

val ExtrinsicBuilder.people: PeopleCalls
    get() = PeopleCalls(this)

fun PeopleCalls.setPersonalAlias(
    aliasAccountId: AccountId,
    callValidAt: BlockNumber
) {
    extrinsicBuilder.call(
        moduleName = Modules.PEOPLE,
        callName = "set_alias_account",
        arguments = mapOf(
            "account" to aliasAccountId.value,
            "call_valid_at" to callValidAt.value
        )
    )
}

fun PeopleCalls.setPersonalIdAccount(
    personalIdAccount: AccountId,
    callValidAt: BlockNumber
) {
    extrinsicBuilder.call(
        moduleName = Modules.PEOPLE,
        callName = "set_personal_id_account",
        arguments = mapOf(
            "account" to personalIdAccount.value,
            "call_valid_at" to callValidAt.value
        )
    )
}
