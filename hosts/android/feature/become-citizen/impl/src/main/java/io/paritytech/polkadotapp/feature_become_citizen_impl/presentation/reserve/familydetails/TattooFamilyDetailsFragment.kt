package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.familydetails

import androidx.compose.runtime.Composable
import androidx.fragment.app.viewModels
import dagger.hilt.android.AndroidEntryPoint
import io.paritytech.polkadotapp.common.presentation.screens.BaseComposeFragment
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.familydetails.compose.TattooFamilyDetailsScreen

@AndroidEntryPoint
class TattooFamilyDetailsFragment() : BaseComposeFragment<TattooFamilyDetailsViewModel>() {
    override val viewModel: TattooFamilyDetailsViewModel by viewModels()

    @Composable
    override fun Screen() = TattooFamilyDetailsScreen(viewModel)
}
