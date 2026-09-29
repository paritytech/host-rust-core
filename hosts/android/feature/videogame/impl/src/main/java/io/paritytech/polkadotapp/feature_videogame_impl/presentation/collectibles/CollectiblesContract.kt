package io.paritytech.polkadotapp.feature_videogame_impl.presentation.collectibles

import android.webkit.WebView
import io.paritytech.polkadotapp.common.presentation.loading.LoadingState
import kotlinx.coroutines.flow.StateFlow

interface CollectiblesContract {
    val state: StateFlow<LoadingState<WebView>>

    fun onBackPressed()
}
