package io.paritytech.polkadotapp.feature_products_api.domain

import io.paritytech.polkadotapp.feature_products_api.model.ProductId

/**
 * The dotNS identity of the funding product the app launches from its own UI, unlike the
 * governance-reserved ones in [io.paritytech.polkadotapp.feature_products_api.model.derivation.ReservedProductIds].
 *
 * Configured remotely, so it can be repointed without a release.
 */
interface FundingDomainProvider {
    /** The bare dotNS label the funding product is served under, e.g. `getcash`. */
    suspend fun getFundingDomain(): Result<String>

    /** [getFundingDomain] resolved against the active network TLD, e.g. `getcash.dot`. */
    suspend fun getFundingProductId(): Result<ProductId>
}
