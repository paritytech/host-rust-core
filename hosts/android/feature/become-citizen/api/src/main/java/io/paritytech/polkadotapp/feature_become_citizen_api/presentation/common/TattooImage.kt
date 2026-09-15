package io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common

import androidx.compose.runtime.Immutable
import io.paritytech.polkadotapp.common.data.image.loadables.ImageLoadable
import io.paritytech.polkadotapp.common.data.image.loadables.JsImageLoadable
import io.paritytech.polkadotapp.common.data.image.loadables.UrlImageLoadable

@Immutable
sealed interface TattooImage {
    companion object {
        val Empty = ByUrl(object : UrlImageLoadable {
            override suspend fun getUrl(): String? = null
        })
    }

    val loadable: ImageLoadable

    class ByUrl(override val loadable: UrlImageLoadable) : TattooImage
    class ByJs(override val loadable: JsImageLoadable) : TattooImage
}
