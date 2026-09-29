package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.fragment.app.viewModels
import dagger.hilt.android.AndroidEntryPoint
import io.paritytech.polkadotapp.common.presentation.formatters.time.LocalTimeFormatter
import io.paritytech.polkadotapp.common.presentation.formatters.time.TimeFormatter
import io.paritytech.polkadotapp.common.presentation.screens.BaseComposeFragment
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.VideoGamePlayScreen
import javax.inject.Inject

@AndroidEntryPoint
class VideoGamePlayFragment : BaseComposeFragment<VideoGamePlayViewModel>() {
    override val viewModel: VideoGamePlayViewModel by viewModels()

    @Inject
    lateinit var timeFormatter: TimeFormatter

    @Composable
    override fun Screen() {
        CompositionLocalProvider(
            LocalTimeFormatter provides timeFormatter
        ) {
            VideoGamePlayScreen(viewModel)
        }
    }
}
