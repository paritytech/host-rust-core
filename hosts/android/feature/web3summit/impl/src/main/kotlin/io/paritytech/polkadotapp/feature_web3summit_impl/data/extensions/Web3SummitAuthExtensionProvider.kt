package io.paritytech.polkadotapp.feature_web3summit_impl.data.extensions

import io.novasama.substrate_sdk_android.runtime.extrinsic.v5.transactionExtension.TransactionExtension
import io.paritytech.polkadotapp.chains.multiNetwork.KnownChains
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.feature_transactions.api.data.extensions.DefaultTransactionExtensionProvider
import io.paritytech.polkadotapp.feature_web3summit_impl.data.keys.Web3SummitAuthKeypairProvider
import javax.inject.Inject

class Web3SummitAuthExtensionProvider @Inject constructor(
    knownChains: KnownChains,
    private val keypairProvider: Web3SummitAuthKeypairProvider,
) : DefaultTransactionExtensionProvider {
    private val allowedChains = listOf(knownChains.people, knownChains.assetHub)

    override fun provideFor(chainId: ChainId): TransactionExtension? {
        return if (chainId in allowedChains) {
            AuthorizeValueTransferExtension(keypairProvider)
        } else {
            null
        }
    }
}
