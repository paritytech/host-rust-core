package io.paritytech.polkadotapp.feature_products_impl.domain.webView

import io.paritytech.polkadotapp.common.utils.toCanonicalDotHost
import io.paritytech.polkadotapp.feature_dotns_api.domain.DotNsTldProvider
import io.paritytech.polkadotapp.feature_dotns_api.presentation.DotNsServingHostResolver
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_products_impl.domain.usecase.ResolveProductUseCase
import javax.inject.Inject

/**
 * A manifest product's content lives on its `app.<base>` subname; the canonical base host has no
 * archive of its own. Legacy products serve from the base host, so for them this is identity.
 */
class ProductServingHostResolver @Inject constructor(
    private val resolveProductUseCase: ResolveProductUseCase,
    private val dotNsTldProvider: DotNsTldProvider,
) : DotNsServingHostResolver {
    override suspend fun servingHostFor(requestHost: String): String {
        // Settled by the time a request is intercepted, since the client awaits it first.
        val tld = dotNsTldProvider.getTld().getOrNull() ?: return requestHost
        // Archives are keyed by the canonical dotNS name, so a `.dot.li` mirror maps to it as well.
        val host = requestHost.toCanonicalDotHost()
        val productId = ProductId.fromString(host, tld).getOrNull() ?: return requestHost
        // A host that already names an executable is served by that executable's own archive.
        if (!productId.value.equals(host, ignoreCase = true)) return host

        val resolved = resolveProductUseCase.resolve(productId).getOrNull() ?: return host

        return resolved.executables.app?.host?.value ?: host
    }
}
