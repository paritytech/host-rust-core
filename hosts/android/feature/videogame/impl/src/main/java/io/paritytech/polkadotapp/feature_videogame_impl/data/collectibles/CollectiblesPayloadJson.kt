package io.paritytech.polkadotapp.feature_videogame_impl.data.collectibles

import io.paritytech.polkadotapp.feature_videogame_impl.domain.collectibles.CollectionInput
import io.paritytech.polkadotapp.feature_videogame_impl.domain.collectibles.OwnedNft
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

internal object CollectiblesPayloadJson {
    fun encodeCollection(json: Json, input: CollectionInput): String =
        json.encodeToString(CollectionInputJson.serializer(), input.toJson())

    fun encodeNft(json: Json, item: OwnedNft): String =
        json.encodeToString(OwnedNftJson.serializer(), item.toJson())
}

@Serializable
private data class CollectionInputJson(
    val owned: List<OwnedNftJson>,
    val displayName: String? = null
)

@Serializable
private data class OwnedNftJson(
    val hash: String,
    val mintedAt: Long? = null,
    val pending: Boolean? = null
)

private fun CollectionInput.toJson() = CollectionInputJson(
    owned = owned.map { it.toJson() },
    displayName = displayName
)

private fun OwnedNft.toJson() = OwnedNftJson(
    hash = hash,
    mintedAt = mintedAt,
    pending = pending
)
