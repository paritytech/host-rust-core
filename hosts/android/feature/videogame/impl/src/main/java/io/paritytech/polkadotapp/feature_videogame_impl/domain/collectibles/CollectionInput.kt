package io.paritytech.polkadotapp.feature_videogame_impl.domain.collectibles

data class CollectionInput(
    val owned: List<OwnedNft>,
    val displayName: String?
)

data class OwnedNft(
    val hash: String,
    val mintedAt: Long?,
    val pending: Boolean?
)
