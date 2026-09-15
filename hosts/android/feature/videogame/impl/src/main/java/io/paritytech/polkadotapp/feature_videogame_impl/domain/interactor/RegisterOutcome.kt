package io.paritytech.polkadotapp.feature_videogame_impl.domain.interactor

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainAssetWithAmount

internal sealed interface RegisterOutcome {
    data object Submitted : RegisterOutcome

    data class NeedsDeposit(val requiredDeposit: ChainAssetWithAmount) : RegisterOutcome
}
