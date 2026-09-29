package io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.deposit

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.asset
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.withAmount
import io.paritytech.polkadotapp.feature_tokens_api.presentation.mapper.TokenAmountMapper
import io.paritytech.polkadotapp.feature_tokens_api.presentation.model.TokenAmountModel
import io.paritytech.polkadotapp.feature_videogame_impl.domain.bot.messages.deposit.model.DepositContent
import javax.inject.Inject

class DepositMessageFormatter @Inject constructor(
    private val chainRegistry: ChainRegistry,
    private val tokenAmountMapper: TokenAmountMapper,
) {
    suspend fun formatAmount(content: DepositContent): TokenAmountModel {
        val asset = chainRegistry.asset(content.asset.chainId, content.asset.assetId)
        val assetWithAmount = asset.withAmount(content.amount)
        return tokenAmountMapper.mapFrom(assetWithAmount)
    }
}
