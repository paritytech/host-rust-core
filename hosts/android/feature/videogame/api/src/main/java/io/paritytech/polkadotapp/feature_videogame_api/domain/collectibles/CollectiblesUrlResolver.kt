package io.paritytech.polkadotapp.feature_videogame_api.domain.collectibles

import android.net.Uri

interface CollectiblesUrlResolver {
    suspend fun resolveUrl(): Uri?
}
