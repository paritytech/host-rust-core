package io.paritytech.polkadotapp.app.root.deeplink.product

import android.net.Uri
import io.paritytech.polkadotapp.app.root.presentation.root.RootRouter
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.presentation.deeplink.DeepLinkHandler
import io.paritytech.polkadotapp.common.presentation.deeplink.DeepLinkHandler.Companion.WEB_HTTPS_SCHEME
import io.paritytech.polkadotapp.common.presentation.deeplink.DeeplinkProcessingOutcome
import io.paritytech.polkadotapp.common.utils.CoroutineDispatchers
import io.paritytech.polkadotapp.common.utils.FeatureOption
import io.paritytech.polkadotapp.common.utils.isEnabled
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.data.repository.awaitAccountsInitialized
import io.paritytech.polkadotapp.feature_dotns_api.domain.DotNsTld
import io.paritytech.polkadotapp.feature_dotns_api.domain.DotNsTldProvider
import io.paritytech.polkadotapp.feature_dotns_api.domain.DotNsUtils
import io.paritytech.polkadotapp.feature_products_api.domain.FundingDomainProvider
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_products_api.presentation.SpaBrowserPayload
import kotlinx.coroutines.withContext
import javax.inject.Inject

internal class ProductSpaDeepLinkHandler @Inject constructor(
    private val coroutineDispatchers: CoroutineDispatchers,
    private val accountRepository: AccountRepository,
    private val rootRouter: RootRouter,
    private val dotNsTldProvider: DotNsTldProvider,
    private val fundingDomainProvider: FundingDomainProvider,
) : DeepLinkHandler {
    override suspend fun canHandle(data: Uri): Boolean {
        val tld = dotNsTldProvider.currentTldOrNull() ?: return false
        if (!DotNsUtils.isDotDomain(data, tld)) return false

        return FeatureOption.ARBITRARY_PRODUCTS.isEnabled || data.isBuiltInProduct(tld)
    }

    // The app still owns its own dotNS destinations when arbitrary ones are off, so Get CASH links keep working.
    private suspend fun Uri.isBuiltInProduct(tld: DotNsTld): Boolean {
        val fundingProductId = fundingDomainProvider.getFundingProductId().getOrNull() ?: return false

        return ProductId.fromUrl(asWebUri(), tld).getOrNull() == fundingProductId
    }

    // Swaps the scheme rather than prefixing it: ensureHttpsProtocol would mangle a polkadotapp:// deeplink.
    private fun Uri.asWebUri(): Uri = buildUpon().scheme(WEB_HTTPS_SCHEME).build()

    context(scope: ComputationalScope)
    override suspend fun handle(data: Uri): Result<DeeplinkProcessingOutcome> =
        withContext(coroutineDispatchers.io) {
            dotNsTldProvider.getTld().mapCatching { tld ->
                accountRepository.awaitAccountsInitialized()

                val normalized = DotNsUtils.normalize(data.asWebUri(), tld)
                    ?: error("Not a $tld domain: $data")

                DeeplinkProcessingOutcome.Navigate {
                    rootRouter.openSpaBrowser(SpaBrowserPayload.ByUrl(normalized.toString()))
                }
            }
        }
}
