package io.paritytech.polkadotapp.feature_products_impl.domain.gameReminders

import android.net.Uri
import io.paritytech.polkadotapp.common.presentation.deeplink.DeepLinkHandler

/** `polkadotapp://gamereminder?productId=<id>`, the target of a game reminder notification. */
internal object GameReminderDeeplink {
    private const val HOST = "gamereminder"
    private const val PRODUCT_ID_PARAM = "productId"

    fun build(productId: String): Uri = Uri.Builder()
        .scheme(DeepLinkHandler.APP_SCHEME)
        .authority(HOST)
        .appendQueryParameter(PRODUCT_ID_PARAM, productId)
        .build()

    fun matches(data: Uri): Boolean = data.scheme == DeepLinkHandler.APP_SCHEME && data.host == HOST

    fun productId(data: Uri): String? = data.getQueryParameter(PRODUCT_ID_PARAM)?.takeIf { it.isNotBlank() }
}
