package io.paritytech.polkadotapp.feature_people_impl.data.signer.origins.extension

import io.novasama.substrate_sdk_android.runtime.extrinsic.v5.transactionExtension.TransactionExtension

abstract class AsPersonTransactionExtension : TransactionExtension {
    final override val name: String = "AsPerson"

    final override suspend fun implicit(): Any? {
        return null
    }
}
