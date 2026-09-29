package io.paritytech.polkadotapp.feature_vouchers_impl.data.signer.extension

import io.novasama.substrate_sdk_android.runtime.RuntimeSnapshot
import io.novasama.substrate_sdk_android.runtime.extrinsic.v5.transactionExtension.InheritedImplication
import io.novasama.substrate_sdk_android.runtime.extrinsic.v5.transactionExtension.TransactionExtension

class ProvideForVoucherClaimer : TransactionExtension {
    override val name: String = "ProvideForVoucherClaimer"

    override suspend fun explicit(
        inheritedImplication: InheritedImplication,
        runtimeSnapshot: RuntimeSnapshot
    ): Any? = null

    override suspend fun implicit(): Any? = null
}
