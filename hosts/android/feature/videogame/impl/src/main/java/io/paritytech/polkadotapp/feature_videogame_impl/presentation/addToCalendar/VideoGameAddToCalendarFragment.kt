package io.paritytech.polkadotapp.feature_videogame_impl.presentation.addToCalendar

import androidx.compose.runtime.Composable
import androidx.fragment.app.viewModels
import dagger.hilt.android.AndroidEntryPoint
import io.paritytech.polkadotapp.common.presentation.screens.BaseComposeFragment
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.addToCalendar.compose.VideoGameAddToCalendarScreen

@AndroidEntryPoint
class VideoGameAddToCalendarFragment : BaseComposeFragment<VideoGameAddToCalendarViewModel>() {
    override val viewModel: VideoGameAddToCalendarViewModel by viewModels()

    @Composable
    override fun Screen() = VideoGameAddToCalendarScreen(viewModel)
}
