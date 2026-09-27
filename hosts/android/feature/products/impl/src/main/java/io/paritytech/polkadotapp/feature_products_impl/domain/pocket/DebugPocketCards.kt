package io.paritytech.polkadotapp.feature_products_impl.domain.pocket

import android.content.SharedPreferences
import androidx.core.content.edit
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.feature_products_api.domain.pocket.PocketCardId
import io.paritytech.polkadotapp.feature_products_api.model.PocketCardDefinition
import io.paritytech.polkadotapp.feature_products_api.model.PocketCardPreview
import io.paritytech.polkadotapp.feature_products_api.model.ProductId

/** The card a debug-supplied worker declares, so a worker served from a laptop can carry one. */
data class DebugPocketCard(
    val cardId: PocketCardId,
    val title: String,
    val previewUrl: String,
)

/**
 * A card spec entered in the debug menu, alongside that product's worker URL.
 *
 * Kept out of the database on purpose: this is a developer's scratch setting, not app state worth a
 * schema revision.
 */
interface DebugPocketCards {
    fun get(productId: ProductId): DebugPocketCard?

    fun set(productId: ProductId, card: DebugPocketCard?)
}

class PrefsDebugPocketCards(
    private val prefs: SharedPreferences,
    private val isDebugBuild: Boolean,
) : DebugPocketCards {
    override fun get(productId: ProductId): DebugPocketCard? {
        if (!isDebugBuild) return null

        val rawId = prefs.getString(productId.key(CARD_ID), null) ?: return null
        val previewUrl = prefs.getString(productId.key(PREVIEW_URL), null)?.takeIf { it.isNotBlank() } ?: return null

        // Screened with the rules the manifest path uses, so a debug card cannot carry an id the
        // core would refuse at the first wire call. A rejected one reads as no card at all.
        val cardId = runCatching { PocketCardIdentifier.screen(rawId) }
            .logFailure("pocket: debug card id for $productId is not usable")
            .getOrNull()
            ?: return null

        return DebugPocketCard(
            cardId = cardId,
            title = prefs.getString(productId.key(TITLE), null)?.takeIf { it.isNotBlank() } ?: cardId.value,
            previewUrl = previewUrl,
        )
    }

    override fun set(productId: ProductId, card: DebugPocketCard?) {
        prefs.edit {
            putString(productId.key(CARD_ID), card?.cardId?.value)
            putString(productId.key(TITLE), card?.title)
            putString(productId.key(PREVIEW_URL), card?.previewUrl)
        }
    }

    private fun ProductId.key(field: String) = "$value.$field"

    private companion object {
        const val CARD_ID = "card_id"
        const val TITLE = "title"
        const val PREVIEW_URL = "preview_url"
    }
}

fun DebugPocketCard.toDefinition(): PocketCardDefinition = PocketCardDefinition(
    id = cardId,
    title = title,
    preview = PocketCardPreview.Url(previewUrl),
)
