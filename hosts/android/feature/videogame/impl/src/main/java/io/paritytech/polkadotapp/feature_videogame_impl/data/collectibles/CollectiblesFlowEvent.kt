package io.paritytech.polkadotapp.feature_videogame_impl.data.collectibles

sealed interface CollectiblesFlowEvent {
    data object Ready : CollectiblesFlowEvent
    data class GalleryShown(val count: Int) : CollectiblesFlowEvent
    data class ItemOpened(val hash: String) : CollectiblesFlowEvent
    data class ItemClosed(val hash: String) : CollectiblesFlowEvent
    data class Error(val phase: String, val detail: String?) : CollectiblesFlowEvent
    data object Close : CollectiblesFlowEvent
    data class Unknown(val type: String) : CollectiblesFlowEvent
}
