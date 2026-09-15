package io.paritytech.polkadotapp.feature_videogame_impl.data

import io.novasama.substrate_sdk_android.runtime.extrinsic.builder.ExtrinsicBuilder
import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchPublicKey
import io.paritytech.polkadotapp.chains.util.EncodedArguments.Companion.autoEncodedArgs
import io.paritytech.polkadotapp.chains.util.Modules
import io.paritytech.polkadotapp.chains.util.call
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.RegistrationOwnershipProof
import io.paritytech.polkadotapp.feature_vouchers_api.domain.models.Voucher
import io.paritytech.polkadotapp.feature_vouchers_api.domain.models.publicKey

@JvmInline
value class ScoreCalls(val extrinsicBuilder: ExtrinsicBuilder)

val ExtrinsicBuilder.score: ScoreCalls
    get() = ScoreCalls(this)

fun ScoreCalls.register(proof: RegistrationOwnershipProof?) {
    extrinsicBuilder.call(
        moduleName = Modules.SCORE,
        callName = "register",
        arguments = autoEncodedArgs("key" to proof)
    )
}

fun ScoreCalls.redeemCredit(voucherPublicKey: BandersnatchPublicKey) {
    extrinsicBuilder.call(
        moduleName = Modules.SCORE,
        callName = "redeem_credit",
        arguments = autoEncodedArgs("voucher" to voucherPublicKey)
    )
}

fun ScoreCalls.redeemCredit(voucher: Voucher) {
    redeemCredit(voucher.publicKey())
}
