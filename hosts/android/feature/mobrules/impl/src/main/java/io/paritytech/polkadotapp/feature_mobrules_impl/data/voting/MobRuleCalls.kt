package io.paritytech.polkadotapp.feature_mobrules_impl.data.voting

import io.novasama.substrate_sdk_android.runtime.extrinsic.builder.ExtrinsicBuilder
import io.novasama.substrate_sdk_android.runtime.extrinsic.call
import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchPublicKey
import io.paritytech.polkadotapp.chains.util.Modules
import io.paritytech.polkadotapp.chains.util.scaleEncodeSerializable
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.model.MobRuleCaseId
import io.paritytech.polkadotapp.feature_mobrules_impl.domain.voting.model.MobRuleVote
import io.paritytech.polkadotapp.feature_vouchers_api.domain.models.Voucher
import io.paritytech.polkadotapp.feature_vouchers_api.domain.models.publicKey

@JvmInline
value class MobRuleCalls(val extrinsicBuilder: ExtrinsicBuilder)

val ExtrinsicBuilder.mobRule: MobRuleCalls
    get() = MobRuleCalls(this)

fun MobRuleCalls.vote(caseId: MobRuleCaseId, vote: MobRuleVote) {
    extrinsicBuilder.call(
        moduleName = Modules.MOB_RULE,
        callName = "vote",
        arguments = mapOf(
            "case_index" to caseId,
            "opinion" to vote.scaleEncodeSerializable(),
        )
    )
}

fun MobRuleCalls.claimVotes(caseIndices: List<MobRuleCaseId>) {
    extrinsicBuilder.call(
        moduleName = Modules.MOB_RULE,
        callName = "claim_votes",
        arguments = mapOf(
            "case_indices" to caseIndices
        )
    )
}

fun MobRuleCalls.claimCredit() {
    extrinsicBuilder.call(
        moduleName = Modules.MOB_RULE,
        callName = "claim_credit",
        arguments = emptyMap()
    )
}

fun MobRuleCalls.payoutRewards(bandersnatchPublicKey: BandersnatchPublicKey) {
    extrinsicBuilder.call(
        moduleName = Modules.MOB_RULE,
        callName = "payout_rewards",
        arguments = mapOf(
            "voucher" to bandersnatchPublicKey.value
        )
    )
}

fun MobRuleCalls.payoutRewards(voucher: Voucher) {
    payoutRewards(voucher.publicKey())
}
