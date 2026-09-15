package io.paritytech.polkadotapp.feature_videogame_impl.presentation.gameResults

import androidx.compose.runtime.Composable
import androidx.fragment.app.viewModels
import dagger.hilt.android.AndroidEntryPoint
import io.paritytech.polkadotapp.common.presentation.screens.BaseComposeFragment
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.gameResults.compose.GameResultsScreen

@AndroidEntryPoint
class GameResultsFragment : BaseComposeFragment<GameResultsViewModel>() {
    override val viewModel: GameResultsViewModel by viewModels()

    @Composable
    override fun Screen() {
        GameResultsScreen(viewModel)
    }
}
