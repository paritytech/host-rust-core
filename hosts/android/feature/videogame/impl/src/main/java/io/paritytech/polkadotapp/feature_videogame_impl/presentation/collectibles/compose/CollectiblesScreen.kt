package io.paritytech.polkadotapp.feature_videogame_impl.presentation.collectibles.compose

import android.webkit.WebView
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.paritytech.polkadotapp.common.presentation.loading.LoadingState
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.Close
import io.paritytech.polkadotapp.design.components.progress.LoadingScreenState
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.components.topbar.PolkadotTopBar
import io.paritytech.polkadotapp.design.components.topbar.TopBarTitleAlignment
import io.paritytech.polkadotapp.design.components.topbar.rememberTopBarAction
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.collectibles.CollectiblesContract
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun CollectiblesScreen(contract: CollectiblesContract) {
    BackHandler { contract.onBackPressed() }

    val state by contract.state.collectAsStateWithLifecycle()

    CollectiblesScreenInternal(
        state = state,
        title = stringResource(RCommon.string.collectibles_title),
        onCloseClick = contract::onBackPressed
    )
}

@Composable
private fun CollectiblesScreenInternal(
    state: LoadingState<WebView>,
    title: String,
    onCloseClick: () -> Unit
) {
    PolkadotSurface(color = PolkadotTheme.colors.bg.surface.main) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .safeDrawingPadding(),
            verticalArrangement = Arrangement.Top
        ) {
            PolkadotTopBar(
                title = title,
                titleAlignment = TopBarTitleAlignment.Center,
                navigationAction = rememberTopBarAction(
                    action = onCloseClick,
                    icon = NovaIcons.Close
                )
            )

            PolkadotSurface(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f),
                color = PolkadotTheme.colors.bg.surface.container
            ) {
                CollectiblesContent(state)
            }
        }
    }
}

@Composable
private fun CollectiblesContent(state: LoadingState<WebView>) {
    when (state) {
        is LoadingState.Loading -> LoadingScreenState()
        is LoadingState.Loaded -> AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { state.data }
        )
        is LoadingState.Error -> CollectiblesErrorContent()
    }
}

@Composable
private fun CollectiblesErrorContent() {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .padding(PolkadotTheme.spacings.large),
        contentAlignment = Alignment.Center
    ) {
        NovaText(
            text = stringResource(RCommon.string.collectibles_unavailable),
            textAlign = TextAlign.Center,
            color = PolkadotTheme.colors.fg.secondary
        )
    }
}
