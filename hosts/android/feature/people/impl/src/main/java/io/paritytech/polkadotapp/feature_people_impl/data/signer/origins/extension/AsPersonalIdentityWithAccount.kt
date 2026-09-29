package io.paritytech.polkadotapp.feature_people_impl.data.signer.origins.extension

import io.novasama.substrate_sdk_android.runtime.RuntimeSnapshot
import io.novasama.substrate_sdk_android.runtime.extrinsic.v5.transactionExtension.InheritedImplication
import io.paritytech.polkadotapp.chains.util.findNonceOrThrow

class AsPersonalIdentityWithAccount : AsPersonTransactionExtension() {
    override suspend fun explicit(
        inheritedImplication: InheritedImplication,
        runtimeSnapshot: RuntimeSnapshot
    ): Any {
        val nonce = inheritedImplication.findNonceOrThrow()
        return AsPersonInfo.AsPersonalIdentityWithAccount(nonce).toEncodableInstance()
    }
}
