package io.paritytech.polkadotapp.feature_become_citizen_impl.domain

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.ChainWithAsset
import io.paritytech.polkadotapp.chains.multiNetwork.KnownChains
import io.paritytech.polkadotapp.chains.util.utilityAsset
import io.paritytech.polkadotapp.feature_tokens_api.domain.ChainAssetProvider
import javax.inject.Inject

class RealCandidateDepositAssetProvider @Inject constructor(
    private val knownChains: KnownChains,
    private val chainRegistry: ChainRegistry,
) : ChainAssetProvider {
    override fun chainId() = knownChains.people

    override suspend fun chain() = chainRegistry.getChain(chainId())

    override suspend fun asset() = chain().utilityAsset

    override suspend fun invoke() = ChainWithAsset(chain = chain(), asset = asset())
}
