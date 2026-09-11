package io.paritytech.polkadotapp.feature_vouchers_impl.domain

import io.novasama.substrate_sdk_android.encrypt.junction.JunctionDecoder
import io.novasama.substrate_sdk_android.encrypt.mnemonic.Mnemonic
import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchContext
import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchEntropy
import io.paritytech.polkadotapp.chains.util.KeyPairGenerator
import io.paritytech.polkadotapp.feature_vouchers_api.domain.models.VoucherType
import io.paritytech.polkadotapp.feature_vouchers_impl.data.PRIVACY_VOUCHER

object VoucherEntropyFactory {
    fun create(
        mnemonic: Mnemonic,
        type: VoucherType,
        index: Int
    ): BandersnatchEntropy {
        val path = getDerivationPathFor(index, type)
        val derivedKeypair = KeyPairGenerator.deriveSr25519From(mnemonic, path)

        return BandersnatchEntropy(derivedKeypair.privateKey)
    }

    private fun getDerivationPathFor(index: Int, type: VoucherType): String {
        return JunctionDecoder.HARD_SEPARATOR + BandersnatchContext.PRIVACY_VOUCHER.stringValue +
            JunctionDecoder.HARD_SEPARATOR + type.junction +
            JunctionDecoder.HARD_SEPARATOR + index
    }
}
