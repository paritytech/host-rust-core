package io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.model

data class ChunkIndex(val index: Int, val totalChunks: Int) {
    companion object {
        fun singleChunk(): ChunkIndex = ChunkIndex(index = 0, totalChunks = 1)

        fun firstChunkOf(totalChunks: Int) = ChunkIndex(index = 0, totalChunks = totalChunks)
    }

    val isLast
        get() = index == totalChunks - 1

    fun nextChunk(): ChunkIndex {
        return if (isLast) this else copy(index = index + 1)
    }
}
