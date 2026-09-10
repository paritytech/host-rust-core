package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.video.preview

import androidx.compose.runtime.Composable
import androidx.fragment.app.viewModels
import dagger.hilt.android.AndroidEntryPoint
import io.paritytech.polkadotapp.common.presentation.screens.BaseComposeFragment
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.video.preview.compose.EvidenceVideoPreviewScreen

@AndroidEntryPoint
class EvidenceVideoPreviewFragment : BaseComposeFragment<EvidenceVideoPreviewViewModel>() {
    override val viewModel by viewModels<EvidenceVideoPreviewViewModel>()

    @Composable
    override fun Screen() {
        EvidenceVideoPreviewScreen(viewModel)
    }
}
