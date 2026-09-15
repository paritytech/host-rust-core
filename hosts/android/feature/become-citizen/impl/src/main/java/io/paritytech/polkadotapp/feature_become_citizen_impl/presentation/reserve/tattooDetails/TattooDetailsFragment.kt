package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.tattooDetails

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.fragment.app.viewModels
import dagger.hilt.android.AndroidEntryPoint
import io.paritytech.polkadotapp.common.presentation.formatters.time.LocalTimeFormatter
import io.paritytech.polkadotapp.common.presentation.formatters.time.TimeFormatter
import io.paritytech.polkadotapp.common.presentation.screens.BaseComposeFragment
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.tattooDetails.compose.TattooDetailsScreen
import javax.inject.Inject

@AndroidEntryPoint
class TattooDetailsFragment : BaseComposeFragment<TattooDetailsViewModel>() {
    override val viewModel by viewModels<TattooDetailsViewModel>()

    @Inject
    lateinit var timeFormatter: TimeFormatter

    @Composable
    override fun Screen() {
        CompositionLocalProvider(
            LocalTimeFormatter provides timeFormatter
        ) {
            TattooDetailsScreen(viewModel)
        }
    }
}
