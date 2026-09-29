package io.paritytech.polkadotapp.feature_videogame_impl.domain.bot.messages.deposit.model

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainAssetId
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.chains.network.binding.Balance
import kotlinx.serialization.Serializable

@Serializable
data class DepositContent(
    val amount: Balance,
    val asset: Asset,
) {
    @Serializable
    class Asset(val chainId: ChainId, val assetId: ChainAssetId)
}
