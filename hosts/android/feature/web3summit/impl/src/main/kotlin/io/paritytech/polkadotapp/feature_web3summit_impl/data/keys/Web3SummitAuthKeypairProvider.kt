package io.paritytech.polkadotapp.feature_web3summit_impl.data.keys

import io.novasama.substrate_sdk_android.encrypt.EncryptionType
import io.novasama.substrate_sdk_android.encrypt.MultiChainEncryption
import io.novasama.substrate_sdk_android.encrypt.Signer
import io.novasama.substrate_sdk_android.encrypt.keypair.Ed25519Utils
import io.novasama.substrate_sdk_android.encrypt.keypair.Keypair
import io.novasama.substrate_sdk_android.extensions.fromHex
import io.paritytech.polkadotapp.feature_web3summit_impl.BuildConfig
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class Web3SummitAuthKeypairProvider @Inject constructor() {
    private val keypair: Keypair by lazy {
        val seed = BuildConfig.W3S_AUTH_KEY.fromHex()
        require(seed.size == ED25519_SEED_SIZE) {
            "W3S_AUTH_KEY must be a 32-byte ed25519 seed (got ${seed.size} bytes)"
        }
        Ed25519Utils.createKeypair(seed)
    }

    fun sign(message: ByteArray): ByteArray {
        return Signer.sign(
            multiChainEncryption = MultiChainEncryption.Substrate(EncryptionType.ED25519),
            message = message,
            keypair = keypair,
        ).signature
    }

    private companion object {
        const val ED25519_SEED_SIZE = 32
    }
}
