package io.paritytech.polkadotapp.feature_products_impl.domain.product

import io.paritytech.polkadotapp.common.utils.flatMap
import io.paritytech.polkadotapp.common.utils.runCancellableCatching
import io.paritytech.polkadotapp.feature_dotns_api.domain.DotNsResolver
import io.paritytech.polkadotapp.feature_dotns_api.presentation.DotNsServingHostResolver
import io.paritytech.polkadotapp.feature_products_api.domain.product.ProductContentWarmUp
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import javax.inject.Inject

/**
 * Asks for exactly what the WebView will ask for when the product loads, so both land on the same
 * cache entry: the resolver holds its lock across a fetch, and the load joins it instead of
 * starting a second one.
 */
class RealProductContentWarmUp @Inject constructor(
    private val dotNsResolver: DotNsResolver,
    private val servingHostResolver: DotNsServingHostResolver,
) : ProductContentWarmUp {
    override suspend fun warmUp(productId: ProductId): Result<Unit> =
        runCancellableCatching { servingHostResolver.servingHostFor(productId.value) }
            .flatMap { servingHost -> dotNsResolver.resolveToLocalUri(servingHost) }
            .map {}
}
