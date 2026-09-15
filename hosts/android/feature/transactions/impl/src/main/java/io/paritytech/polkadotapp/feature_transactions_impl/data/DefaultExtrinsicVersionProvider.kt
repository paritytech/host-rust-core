package io.paritytech.polkadotapp.feature_transactions_impl.data

import io.novasama.substrate_sdk_android.runtime.extrinsic.ExtrinsicVersion
import io.paritytech.polkadotapp.chains.multiNetwork.KnownChains
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.tools_remoteconfig_api.RemoteConfigService
import io.paritytech.polkadotapp.tools_remoteconfig_api.getSyncedJsonObject
import javax.inject.Inject

interface DefaultExtrinsicVersionProvider {
    suspend fun getDefaultExtrinsicVersion(chainId: ChainId, isSigned: Boolean): Result<ExtrinsicVersion>
}

class RealDefaultExtrinsicVersionProvider @Inject constructor(
    private val knownChains: KnownChains,
    private val remoteConfigService: RemoteConfigService,
) : DefaultExtrinsicVersionProvider {
    private companion object {
        const val TX_EXTENSION_VERSIONS_KEY = "transaction_extension_versions"
        const val TX_EXTENSION_VERSION_DEFAULT = 0
    }

    override suspend fun getDefaultExtrinsicVersion(chainId: ChainId, isSigned: Boolean): Result<ExtrinsicVersion> {
        val usesV5 = when (chainId) {
            knownChains.people -> true
            knownChains.assetHub -> !isSigned
            else -> false
        }

        return if (usesV5) {
            getTransactionExtensionVersion(chainId).map(ExtrinsicVersion::V5)
        } else {
            Result.success(ExtrinsicVersion.V4)
        }
    }

    private suspend fun getTransactionExtensionVersion(chainId: ChainId): Result<Byte> {
        // Gson receives only the raw Class, so map values arrive as Double regardless of the declared type
        return remoteConfigService.getSyncedJsonObject<Map<String, Number>>(TX_EXTENSION_VERSIONS_KEY)
            .map { versions -> (versions[chainId] ?: TX_EXTENSION_VERSION_DEFAULT).toByte() }
    }
}
