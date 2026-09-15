package io.paritytech.polkadotapp.feature_videogame_impl.presentation.collectibles

import android.webkit.WebView
import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.presentation.loading.LoadingState
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.common.utils.awaitTrue
import io.paritytech.polkadotapp.common.utils.flowOf
import io.paritytech.polkadotapp.common.utils.withLoading
import io.paritytech.polkadotapp.feature_videogame_api.domain.collectibles.CollectiblesUrlResolver
import io.paritytech.polkadotapp.feature_videogame_impl.VideoGameRouter
import io.paritytech.polkadotapp.feature_videogame_impl.data.collectibles.CollectiblesFlowEvent
import io.paritytech.polkadotapp.feature_videogame_impl.data.collectibles.CollectiblesWebViewProvider
import io.paritytech.polkadotapp.feature_videogame_impl.domain.collectibles.CollectiblesInteractor
import io.paritytech.polkadotapp.feature_videogame_impl.domain.collectibles.CollectionInput
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject

@HiltViewModel
class CollectiblesViewModel @Inject constructor(
    private val webViewProvider: CollectiblesWebViewProvider,
    private val urlResolver: CollectiblesUrlResolver,
    private val interactor: CollectiblesInteractor,
    private val router: VideoGameRouter
) : BaseViewModel(), CollectiblesContract {
    private var bundle: CollectiblesWebViewProvider.Bundle? = null

    override val state: StateFlow<LoadingState<WebView>> = flowOf {
        val url = urlResolver.resolveUrl() ?: throw CollectiblesError.UrlUnavailable
        val newBundle = webViewProvider.create(url)
        bundle = newBundle
        attachBundle(newBundle)
        newBundle.webView
    }
        .withLoading("Collectibles")
        .stateIn(this, SharingStarted.Eagerly, LoadingState.Loading)

    override fun onCleared() {
        bundle?.destroy()
        super.onCleared()
    }

    override fun onBackPressed() {
        router.back()
    }

    private fun attachBundle(bundle: CollectiblesWebViewProvider.Bundle) {
        bundle.bridge.events
            .onEach(::handleEvent)
            .launchIn(this)
        launch {
            bundle.pageFinished.awaitTrue()
            deliverCollection(bundle)
        }
    }

    private suspend fun deliverCollection(bundle: CollectiblesWebViewProvider.Bundle) {
        val input = interactor.loadCollection().getOrElse { error ->
            Timber.w(error, "failed to load collection")
            CollectionInput(owned = emptyList(), displayName = null)
        }
        bundle.sender.deliverCollection(input)
    }

    private fun handleEvent(event: CollectiblesFlowEvent) {
        when (event) {
            CollectiblesFlowEvent.Ready -> Timber.d("flow.ready")
            is CollectiblesFlowEvent.GalleryShown -> Timber.d("flow.gallery_shown count=${event.count}")
            is CollectiblesFlowEvent.ItemOpened -> Timber.d("flow.item_opened hash=${event.hash}")
            is CollectiblesFlowEvent.ItemClosed -> Timber.d("flow.item_closed hash=${event.hash}")
            is CollectiblesFlowEvent.Error ->
                Timber.w("flow.error phase=${event.phase} detail=${event.detail}")
            CollectiblesFlowEvent.Close -> {
                Timber.d("flow.close")
                router.back()
            }
            is CollectiblesFlowEvent.Unknown -> Timber.w("unknown event type=${event.type}")
        }
    }
}
