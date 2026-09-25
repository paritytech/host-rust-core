package io.paritytech.polkadotapp.feature_products_impl.domain.webView

import android.view.ViewGroup
import android.webkit.WebView
import io.paritytech.polkadotapp.common.utils.CoroutineDispatchers
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_products_impl.domain.hostApi.FixedProductId
import io.paritytech.polkadotapp.test_shared.testDispatchers
import io.paritytech.polkadotapp.test_shared.whenever
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test
import org.mockito.Mockito.doAnswer
import org.mockito.Mockito.mock

@OptIn(ExperimentalCoroutinesApi::class)
class WebViewProviderTest {
    private val events = mutableListOf<String>()
    private val host = mock(ViewGroup::class.java)
    private val names = mutableMapOf<WebView, String>()
    private val WebView.name get() = names.getValue(this)

    // Android never revives a WebView whose renderer died. The page only comes back in a fresh
    // WebView that carries the same setup (for a product, the bootstrap with its endpoint), and the
    // screen has to drop the dead one and show the fresh one.
    @Test
    fun `a WebView whose renderer died is replaced by one set up the same way`() = runTest {
        val first = webView("first")
        val second = webView("second")
        val provider = FakeWebViewProvider(testDispatchers(), listOf(first, second).iterator())
        val shown = mutableListOf<WebView?>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { provider.webViews().toList(shown) }

        provider.addWebViewSetup { events += "set up ${it.name}" }
        provider.getWebView()
        provider.loseRenderer(first, this)
        advanceUntilIdle()

        assertEquals(
            Recovery(
                events = listOf("set up first", "detach first", "destroy first", "set up second", "load second $PAGE"),
                shown = listOf(first, null, second),
            ),
            Recovery(events, shown),
        )
    }

    private fun webView(name: String): WebView = mock(WebView::class.java).also { view ->
        whenever(view.parent).thenReturn(host)
        doAnswer { events += "destroy $name" }.`when`(view).destroy()
        doAnswer { events += "load $name ${it.getArgument<String>(0)}" }.`when`(view).loadUrl(PAGE)
        doAnswer { events += "detach $name" }.`when`(host).removeView(view)
        names[view] = name
    }

    private data class Recovery(val events: List<String>, val shown: List<WebView?>)

    private class FakeWebViewProvider(
        dispatchers: CoroutineDispatchers,
        private val views: Iterator<WebView>,
    ) : WebViewProvider(dispatchers) {
        override val callingProductIdProvider = FixedProductId(ProductId.fromStoredValue("product.paseo"))

        override suspend fun createWebView(): WebView = views.next()

        override suspend fun loadInitialContent() = Unit

        fun loseRenderer(dead: WebView, scope: CoroutineScope) = replaceDeadWebView(dead, scope, PAGE)
    }

    private companion object {
        const val PAGE = "https://product.paseo/tab"
    }
}
