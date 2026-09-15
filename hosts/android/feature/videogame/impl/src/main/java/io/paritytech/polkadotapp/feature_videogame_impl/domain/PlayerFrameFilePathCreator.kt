package io.paritytech.polkadotapp.feature_videogame_impl.domain

import io.paritytech.polkadotapp.common.data.storage.file.FileProvider
import io.paritytech.polkadotapp.common.domain.model.AccountId
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class PlayerFrameFilePathCreator @Inject constructor(
    private val fileProvider: FileProvider
) {
    fun getFile(gameIndex: Int, accountId: AccountId): File {
        val relativePath = createRelativeFilePath(gameIndex, accountId)
        return fileProvider.getFileInInternalCacheStorage(relativePath)
    }

    fun getEncodedUri(gameIndex: Int, accountId: AccountId): String {
        val file = getFile(gameIndex, accountId)
        return fileProvider.uriOf(file).toString()
    }

    private fun createRelativeFilePath(gameIndex: Int, accountId: AccountId): String {
        return "game_players/game_${gameIndex}_player_${accountId.value.contentHashCode()}.jpg"
    }
}
