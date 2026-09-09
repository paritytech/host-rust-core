package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.photo.instructions

import androidx.compose.runtime.Composable
import androidx.fragment.app.viewModels
import dagger.hilt.android.AndroidEntryPoint
import io.paritytech.polkadotapp.common.presentation.screens.BaseComposeFragment
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.photo.instructions.compose.EvidencePhotoInstructionScreen

@AndroidEntryPoint
class EvidencePhotoInstructionsFragment : BaseComposeFragment<EvidencePhotoInstructionsViewModel>() {
    override val viewModel by viewModels<EvidencePhotoInstructionsViewModel>()

    @Composable
    override fun Screen() {
        EvidencePhotoInstructionScreen(viewModel)
    }
}
