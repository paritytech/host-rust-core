package io.paritytech.polkadotapp.feature_products_impl.domain.pocket

import io.paritytech.polkadotapp.feature_products_api.domain.pocket.PocketCardKey
import io.paritytech.polkadotapp.feature_products_api.domain.pocket.PocketCollection
import io.paritytech.polkadotapp.feature_products_api.model.JsWidget

/** The collection as the host's own flows see it: the public read side plus the writes only the host makes. */
interface PocketCardStore : PocketCollection {
    /** Inserts a card the user approved, replacing the face of one already present. */
    suspend fun addCard(card: CachedPocketCard)

    /** The newest face held for [key]: bundled for a pinned card, approved for an added one, or the last streamed. */
    suspend fun cachedFace(key: PocketCardKey): JsWidget?

    /** Remembers the newest face the product streamed, so the card has it offline and at cold start. */
    suspend fun cacheFace(key: PocketCardKey, face: JsWidget)
}
