package io.paritytech.polkadotapp.feature_web3summit_impl.data.extensions

import io.novasama.substrate_sdk_android.hash.Hasher.blake2b256
import io.novasama.substrate_sdk_android.runtime.RuntimeSnapshot
import io.novasama.substrate_sdk_android.runtime.extrinsic.v5.transactionExtension.InheritedImplication
import io.novasama.substrate_sdk_android.runtime.extrinsic.v5.transactionExtension.TransactionExtension
import io.paritytech.polkadotapp.feature_web3summit_impl.data.keys.Web3SummitAuthKeypairProvider

/**
 * Signs the inherited implication with the bundled W3S ed25519 key and surfaces the result
 * as `Option<Signature>::Some(sig)` in the runtime's `AuthorizeValueTransfer` slot.
 *
 * Runtime contract: `pallets/value-transfer-auth/src/extension.rs`. Validate hashes the
 * SCALE-encoded inherited implication with blake2_256 and checks the signature against the
 * runtime-bundled ed25519 public key.
 */
class AuthorizeValueTransferExtension(
    private val keypairProvider: Web3SummitAuthKeypairProvider,
) : TransactionExtension {
    override val name: String = "AuthorizeValueTransfer"

    override suspend fun implicit(): Any? = null

    override suspend fun explicit(
        inheritedImplication: InheritedImplication,
        runtimeSnapshot: RuntimeSnapshot,
    ): Any {
        val payloadHash = inheritedImplication.encoded().blake2b256()
        return keypairProvider.sign(payloadHash)
    }
}
