package io.paritytech.polkadotapp.feature_videogame_impl.presentation.collectibles

import androidx.compose.runtime.Composable
import androidx.fragment.app.viewModels
import dagger.hilt.android.AndroidEntryPoint
import io.paritytech.polkadotapp.common.presentation.screens.BaseComposeFragment
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.collectibles.compose.CollectiblesScreen

@AndroidEntryPoint
class CollectiblesFragment : BaseComposeFragment<CollectiblesViewModel>() {
    override val viewModel: CollectiblesViewModel by viewModels()

    @Composable
    override fun Screen() {
        CollectiblesScreen(viewModel)
    }
}
