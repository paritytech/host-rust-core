package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.audio

import android.content.Context
import android.media.MediaPlayer
import dagger.hilt.android.qualifiers.ApplicationContext
import io.paritytech.polkadotapp.feature_videogame_impl.R
import javax.inject.Inject

class ConfettiSoundPlayer @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private var mediaPlayer: MediaPlayer? = null

    fun play() {
        mediaPlayer?.release()
        mediaPlayer = null

        mediaPlayer = MediaPlayer.create(context, R.raw.confetti_pop)?.apply {
            setOnCompletionListener {
                it.release()
                if (mediaPlayer == it) mediaPlayer = null
            }
            start()
        }
    }

    fun release() {
        mediaPlayer?.release()
        mediaPlayer = null
    }
}
