package io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail

import androidx.compose.runtime.Composable
import androidx.fragment.app.viewModels
import dagger.hilt.android.AndroidEntryPoint
import io.paritytech.polkadotapp.common.presentation.screens.BaseComposeFragment
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.compose.MediaEvidenceDetailScreen

@AndroidEntryPoint
class MediaEvidenceDetailFragment : BaseComposeFragment<MediaEvidenceDetailViewModel>() {
    override val viewModel: MediaEvidenceDetailViewModel by viewModels()

    @Composable
    override fun Screen() = MediaEvidenceDetailScreen(viewModel)
}
