package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.helpers

import android.graphics.Bitmap
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex
import io.paritytech.polkadotapp.feature_videogame_impl.data.VideoGameTimings
import io.paritytech.polkadotapp.feature_videogame_impl.domain.PlayerFrameFilePathCreator
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import timber.log.Timber
import java.io.FileOutputStream
import javax.inject.Inject

class PlayerFrameCapturer @Inject constructor(
    private val filePathCreator: PlayerFrameFilePathCreator,
) {
    companion object {
        val CAPTURE_DELAY = VideoGameTimings.HOST_ACTIVE_MINIMUM / 2
    }

    suspend fun capture(gameIndex: GameIndex, accountId: AccountId, bitmap: Bitmap) = withContext(Dispatchers.IO) {
        try {
            val file = filePathCreator.getFile(gameIndex.value, accountId)

            FileOutputStream(file).use {
                bitmap.compress(Bitmap.CompressFormat.JPEG, 100, it)
            }
            Timber.d("Player frame captured: ${accountId.value.contentToString()}")
        } catch (e: Exception) {
            Timber.d(e, "Failed to capture player frame: ${accountId.value.contentToString()}")
            bitmap.recycle()
        }
    }
}
