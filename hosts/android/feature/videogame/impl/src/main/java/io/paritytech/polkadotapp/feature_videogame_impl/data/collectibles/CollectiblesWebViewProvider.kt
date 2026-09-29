package io.paritytech.polkadotapp.feature_videogame_impl.data.collectibles

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import android.webkit.ConsoleMessage
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import dagger.hilt.android.qualifiers.ApplicationContext
import io.paritytech.polkadotapp.feature_dotns_api.domain.DotNsResolver
import io.paritytech.polkadotapp.feature_dotns_api.domain.DotNsTldProvider
import io.paritytech.polkadotapp.feature_dotns_api.presentation.DotNsServingHostResolver
import io.paritytech.polkadotapp.feature_dotns_api.presentation.DotNsWebViewClient
import io.paritytech.polkadotapp.feature_videogame_impl.BuildConfig
import io.paritytech.polkadotapp.feature_videogame_impl.di.WebViewPayloadJson
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.json.Json
import timber.log.Timber
import javax.inject.Inject

class CollectiblesWebViewProvider @Inject constructor(
    @ApplicationContext private val context: Context,
    private val dotNsResolver: DotNsResolver,
    private val dotNsTldProvider: DotNsTldProvider,
    private val servingHostResolver: DotNsServingHostResolver,
    @WebViewPayloadJson private val json: Json
) {
    data class Bundle(
        val webView: WebView,
        val sender: CollectiblesJsSender,
        val bridge: CollectiblesJsBridge,
        val pageFinished: StateFlow<Boolean>
    ) {
        fun destroy() {
            webView.removeJavascriptInterface(JS_INTERFACE_NAME)
            webView.stopLoading()
            webView.destroy()
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    fun create(url: Uri): Bundle {
        if (BuildConfig.DEBUG) {
            WebView.setWebContentsDebuggingEnabled(true)
        }

        val pageFinished = MutableStateFlow(false)
        val bridge = CollectiblesJsBridge()
        val webView = WebView(context).apply {
            with(settings) {
                javaScriptEnabled = true
                domStorageEnabled = true
                allowFileAccess = false
                allowContentAccess = false
                mediaPlaybackRequiresUserGesture = false
                mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
            }
            webViewClient =
                PageFinishedClient(pageFinished, dotNsResolver, dotNsTldProvider, servingHostResolver)
            webChromeClient = ConsoleLoggingChromeClient()
            addJavascriptInterface(bridge, JS_INTERFACE_NAME)
            loadUrl(url.toString())
        }
        return Bundle(
            webView = webView,
            sender = CollectiblesJsSender(webView, json),
            bridge = bridge,
            pageFinished = pageFinished.asStateFlow()
        )
    }

    private class PageFinishedClient(
        private val pageFinished: MutableStateFlow<Boolean>,
        dotNsResolver: DotNsResolver,
        dotNsTldProvider: DotNsTldProvider,
        servingHostResolver: DotNsServingHostResolver,
    ) : DotNsWebViewClient(dotNsResolver, dotNsTldProvider, servingHostResolver) {
        override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
            super.onPageStarted(view, url, favicon)
            Timber.d("[Collectibles] onPageStarted url=$url")
            pageFinished.value = false
        }

        override fun onPageFinished(view: WebView?, url: String?) {
            super.onPageFinished(view, url)
            Timber.d("[Collectibles] onPageFinished url=$url")
            pageFinished.value = true
        }
    }

    private class ConsoleLoggingChromeClient : WebChromeClient() {
        override fun onConsoleMessage(message: ConsoleMessage?): Boolean {
            if (message == null) return false
            val tag = "CollectiblesJS"
            val text = "${message.message()} (@${message.sourceId()}:${message.lineNumber()})"
            when (message.messageLevel()) {
                ConsoleMessage.MessageLevel.ERROR -> Timber.tag(tag).e(text)
                ConsoleMessage.MessageLevel.WARNING -> Timber.tag(tag).w(text)
                ConsoleMessage.MessageLevel.LOG,
                ConsoleMessage.MessageLevel.DEBUG,
                ConsoleMessage.MessageLevel.TIP,
                null -> Timber.tag(tag).d(text)
            }
            return true
        }
    }

    private companion object {
        const val JS_INTERFACE_NAME = "collectibles"
    }
}
