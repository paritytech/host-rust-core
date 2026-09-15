package io.paritytech.polkadotapp.feature_wallet_impl.domain.model

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.chains.network.binding.Balance

data class AssetInfo(
    val asset: Chain.Asset,
    val totalBalance: Balance,
    val spendableBalance: Balance,
    val gainingPrivacyBalance: Balance,
    val pendingBalance: Balance
)
