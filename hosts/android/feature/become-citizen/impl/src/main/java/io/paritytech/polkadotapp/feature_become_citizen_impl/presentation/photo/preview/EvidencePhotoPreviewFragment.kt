package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.photo.preview

import androidx.compose.runtime.Composable
import androidx.fragment.app.viewModels
import dagger.hilt.android.AndroidEntryPoint
import io.paritytech.polkadotapp.common.presentation.screens.BaseComposeFragment
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.photo.preview.compose.EvidencePhotoPreviewScreen

@AndroidEntryPoint
class EvidencePhotoPreviewFragment : BaseComposeFragment<EvidencePhotoPreviewViewModel>() {
    override val viewModel by viewModels<EvidencePhotoPreviewViewModel>()

    @Composable
    override fun Screen() {
        EvidencePhotoPreviewScreen(viewModel)
    }
}
