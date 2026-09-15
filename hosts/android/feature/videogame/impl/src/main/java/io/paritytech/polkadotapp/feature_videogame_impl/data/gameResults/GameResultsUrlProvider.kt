package io.paritytech.polkadotapp.feature_videogame_impl.data.gameResults

import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.feature_dotns_api.domain.DotNsResolver
import io.paritytech.polkadotapp.feature_videogame_impl.BuildConfig
import io.paritytech.polkadotapp.tools_remoteconfig_api.RemoteConfigService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import javax.inject.Inject

/**
 * Resolves the game-results web app URL: DotNs (`game-webview.dot` → local `index.html`),
 * then the Remote Config kill switch, then the bundled fallback. Each level logs its
 * failure and falls through to the next.
 */
interface GameResultsUrlProvider {
    suspend fun resolveUrl(): String
}

class RealGameResultsUrlProvider @Inject constructor(
    private val dotNsResolver: DotNsResolver,
    private val remoteConfigService: RemoteConfigService,
) : GameResultsUrlProvider {
    override suspend fun resolveUrl(): String {
        return resolveFromDotNs() ?: resolveFromRemoteConfig() ?: BUNDLED_FALLBACK_URL
    }

    // runCatching: resolveToLocalUri can throw past its Result (e.g. unregistered DotNs chain).
    private suspend fun resolveFromDotNs(): String? = runCatching {
        val resolved = dotNsResolver.resolveToLocalUri(DOTNS_NAME)
            .logFailure("[GameResults] DotNs resolveToLocalUri failed")
            .getOrNull()
        val path = resolved?.path ?: return@runCatching null
        val index = File(path, INDEX_FILE)
        val exists = withContext(Dispatchers.IO) { index.exists() }
        if (exists) "https://$DOTNS_NAME/" else null
    }
        .logFailure("[GameResults] DotNs resolution failed")
        .getOrNull()

    // getSyncedString: an unsynced first read would return the pre-activation value and
    // silently no-op the ops kill switch (see CrossChainTransfersRepository).
    private suspend fun resolveFromRemoteConfig(): String? = remoteConfigService
        .getSyncedString(REMOTE_CONFIG_KEY)
        .logFailure("[GameResults] Remote Config lookup failed")
        .getOrNull()
        ?.let(::sanitizedHttpUrlOrNull)

    private fun sanitizedHttpUrlOrNull(raw: String): String? = raw
        .trim()
        .removeSurrounding("\"")
        .trim()
        .takeIf { it.startsWith("http://", ignoreCase = true) || it.startsWith("https://", ignoreCase = true) }

    private companion object {
        const val DOTNS_NAME = "game-webview.dot"
        const val INDEX_FILE = "index.html"
        const val REMOTE_CONFIG_KEY = "game_results_fallback_url"
        val BUNDLED_FALLBACK_URL = BuildConfig.GAME_RESULTS_FALLBACK_URL
    }
}
