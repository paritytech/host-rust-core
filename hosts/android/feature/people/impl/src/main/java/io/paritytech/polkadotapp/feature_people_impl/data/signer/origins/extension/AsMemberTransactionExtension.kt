package io.paritytech.polkadotapp.feature_people_impl.data.signer.origins.extension

import io.novasama.substrate_sdk_android.hash.Hasher.blake2b256
import io.novasama.substrate_sdk_android.runtime.RuntimeSnapshot
import io.novasama.substrate_sdk_android.runtime.extrinsic.v5.transactionExtension.InheritedImplication
import io.novasama.substrate_sdk_android.runtime.extrinsic.v5.transactionExtension.TransactionExtension
import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.BandersnatchSecretsStorage
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.sign

class AsMemberTransactionExtension(
    private val candidateMetaId: Long,
    private val bandersnatchSecretsStorage: BandersnatchSecretsStorage,
) : TransactionExtension {
    override val name: String = "AsMember"

    override suspend fun implicit(): Any? = null

    override suspend fun explicit(
        inheritedImplication: InheritedImplication,
        runtimeSnapshot: RuntimeSnapshot,
    ): Any? {
        val message = inheritedImplication.encoded().blake2b256()
        val signature = bandersnatchSecretsStorage.sign(candidateMetaId, message).toDataByteArray()

        return AsMemberInfo.SelfInclude(signature).toEncodableInstance()
    }
}
