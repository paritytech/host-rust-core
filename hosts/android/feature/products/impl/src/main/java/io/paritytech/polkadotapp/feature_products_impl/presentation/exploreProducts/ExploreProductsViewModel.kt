package io.paritytech.polkadotapp.feature_products_impl.presentation.exploreProducts

import androidx.core.net.toUri
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.common.utils.flowOf
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.common.utils.shareInBackground
import io.paritytech.polkadotapp.feature_dotns_api.domain.DotNsTldProvider
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_products_api.presentation.SpaBrowserPayload
import io.paritytech.polkadotapp.feature_products_impl.domain.bot.ProductsBotApiImpl
import io.paritytech.polkadotapp.feature_products_impl.domain.exploreProducts.ExploreProductsService
import io.paritytech.polkadotapp.feature_products_impl.domain.hostApi.HostApiEnvironment
import io.paritytech.polkadotapp.feature_products_impl.domain.hostApi.HostApiSession
import io.paritytech.polkadotapp.feature_products_impl.domain.hostApi.HostCallGroupFactory
import io.paritytech.polkadotapp.feature_products_impl.domain.hostApi.PageLoadInjection
import io.paritytech.polkadotapp.feature_products_impl.domain.hostApi.navigation.NavigationPolicy
import io.paritytech.polkadotapp.feature_products_impl.domain.jsRuntime.WebViewRuntime
import io.paritytech.polkadotapp.feature_products_impl.domain.product.ProductRegistrar
import io.paritytech.polkadotapp.feature_products_impl.domain.product.launchEnsureRegistered
import io.paritytech.polkadotapp.feature_products_impl.domain.webView.BrowserWebViewProvider
import io.paritytech.polkadotapp.feature_products_impl.presentation.productBotManagement.ProductsRouter
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class ExploreProductsViewModel @Inject constructor(
    private val browserWebViewProviderFactory: BrowserWebViewProvider.Factory,
    private val hostCallGroupFactory: HostCallGroupFactory,
    private val sessionFactory: HostApiSession.Factory,
    private val botApiFactory: ProductsBotApiImpl.Factory,
    private val productRegistrar: ProductRegistrar,
    private val router: ProductsRouter,
    private val exploreProductsService: ExploreProductsService,
    private val dotNsTldProvider: DotNsTldProvider,
) : BaseViewModel() {
    private data class SessionComponents(
        val session: HostApiSession,
        val provider: BrowserWebViewProvider,
    )

    private val componentsFlow = flowOf {
        createComponents()
    }.filterNotNull().shareInBackground()

    val webViewFlow = componentsFlow
        .map { it.provider.getWebView() }
        .stateIn(scope = this, started = SharingStarted.Eagerly, initialValue = null)

    init {
        componentsFlow.onEach {
            it.session.initialize()
        }.launchIn(this)
    }

    fun onProductSelected(productId: ProductId) {
        launch { router.openSpaBrowser(SpaBrowserPayload.ByProductId(productId.value)) }
    }

    fun pauseConnections() {
        launch { componentsFlow.first().provider.pauseConnections() }
    }

    fun resumeConnections() {
        launch { componentsFlow.first().provider.resumeConnections() }
    }

    private suspend fun createComponents(): SessionComponents? {
        val exploreUrl = exploreProductsService.getExploreUrl()
            .logFailure("Failed to resolve explore url")
            .getOrNull() ?: return null

        val navigationPolicy = NavigationPolicy.CatalogNavigation(::onProductSelected, dotNsTldProvider)

        val webViewProvider = browserWebViewProviderFactory.create(exploreUrl, navigationPolicy, allowIframes = false, viewModelScope)
        webViewProvider.addOnPageStartedListener { url ->
            dotNsTldProvider.currentTldOrNull()
                ?.let { tld -> ProductId.fromUrl(url.toUri(), tld).getOrNull() }
                ?.let { productRegistrar.launchEnsureRegistered(it) }
        }
        val productIdProvider = webViewProvider.callingProductIdProvider

        val runtime = WebViewRuntime(webViewProvider)

        val botApi = botApiFactory.create(productIdProvider)
        val handlerGroups = hostCallGroupFactory.createShared(botApi, productIdProvider, navigationPolicy)

        val environment = HostApiEnvironment(
            injectionStrategy = PageLoadInjection(
                pageLifecycleSource = webViewProvider,
                coroutineScope = this,
            ),
            handlerGroups = handlerGroups,
        )

        val transport = runtime.createTransport()
        val session = sessionFactory.create(environment, runtime, transport, this)

        return SessionComponents(session, webViewProvider)
    }
}
