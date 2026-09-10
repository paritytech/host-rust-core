package io.paritytech.polkadotapp.feature_products_impl.presentation.spaSheet

import androidx.compose.runtime.Composable
import androidx.fragment.app.viewModels
import dagger.hilt.android.AndroidEntryPoint
import io.paritytech.polkadotapp.common.presentation.screens.BaseComposeBottomSheet
import io.paritytech.polkadotapp.feature_products_impl.presentation.spaSheet.compose.SpaSheetScreen

@AndroidEntryPoint
class SpaSheetBottomSheet : BaseComposeBottomSheet<SpaSheetViewModel>() {
    override val viewModel: SpaSheetViewModel by viewModels()

    @Composable
    override fun Screen() = SpaSheetScreen(viewModel)

    override fun onPause() {
        super.onPause()
        viewModel.pauseConnections()
    }

    override fun onResume() {
        super.onResume()
        viewModel.resumeConnections()
    }
}
