package io.paritytech.polkadotapp.feature_become_citizen_api.data.signer

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.feature_transactions.api.domain.model.TransactionOrigin

interface PostApplyOriginProvider {
    suspend fun postApplyOrigin(chain: Chain): TransactionOrigin
}
