package io.paritytech.polkadotapp.feature_vouchers_api.domain.models

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchAlias
import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchEntropy
import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchPublicKey
import io.paritytech.polkadotapp.bandersnatch_crypto.memberKey
import io.paritytech.polkadotapp.chains.network.binding.Balance

interface Voucher {
    val index: Int
    val type: VoucherType
    val state: VoucherState
    val entropy: BandersnatchEntropy
    val alias: BandersnatchAlias
    val value: Balance
}

fun Voucher.publicKey(): BandersnatchPublicKey {
    return entropy.memberKey()
}

enum class VoucherType(val junction: String) {
    TATTOO_REIMBURSEMENT("tattooReimbursement"),
    REFERRAL("referral"),
    MOB_RULE_REWARD("mobRuleReward"),

    SCORE("scoreReward");

    companion object {
        fun fromJunction(junction: String) = entries.first { it.junction == junction }
    }
}

enum class VoucherState {
    GENERATED, REGISTERED, CLAIMABLE, CLAIMED
}
