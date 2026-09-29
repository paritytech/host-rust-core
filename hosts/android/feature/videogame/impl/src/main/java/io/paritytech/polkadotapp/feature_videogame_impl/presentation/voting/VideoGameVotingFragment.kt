package io.paritytech.polkadotapp.feature_videogame_impl.presentation.voting

import androidx.compose.runtime.Composable
import androidx.fragment.app.viewModels
import dagger.hilt.android.AndroidEntryPoint
import io.paritytech.polkadotapp.common.presentation.screens.BaseComposeFragment
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.voting.compose.VideoGameVotingScreen

@AndroidEntryPoint
class VideoGameVotingFragment : BaseComposeFragment<VideoGameVotingViewModel>() {
    override val viewModel: VideoGameVotingViewModel by viewModels()

    @Composable
    override fun Screen() {
        VideoGameVotingScreen(viewModel)
    }
}
