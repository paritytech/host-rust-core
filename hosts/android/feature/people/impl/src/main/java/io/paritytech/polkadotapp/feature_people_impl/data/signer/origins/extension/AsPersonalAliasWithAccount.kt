package io.paritytech.polkadotapp.feature_people_impl.data.signer.origins.extension

import io.novasama.substrate_sdk_android.runtime.RuntimeSnapshot
import io.novasama.substrate_sdk_android.runtime.extrinsic.v5.transactionExtension.InheritedImplication
import io.paritytech.polkadotapp.chains.util.findNonceOrThrow

class AsPersonalAliasWithAccount : AsPersonTransactionExtension() {
    override suspend fun explicit(
        inheritedImplication: InheritedImplication,
        runtimeSnapshot: RuntimeSnapshot
    ): Any {
        val extension = inheritedImplication.findNonceOrThrow()
        return AsPersonInfo.AsPersonalAliasWithAccount(extension).toEncodableInstance()
    }
}
