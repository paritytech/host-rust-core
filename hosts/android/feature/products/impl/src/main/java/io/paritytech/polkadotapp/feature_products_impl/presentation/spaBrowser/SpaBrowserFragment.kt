package io.paritytech.polkadotapp.feature_products_impl.presentation.spaBrowser

import androidx.compose.runtime.Composable
import androidx.fragment.app.viewModels
import dagger.hilt.android.AndroidEntryPoint
import io.paritytech.polkadotapp.common.presentation.screens.BaseComposeFragment
import io.paritytech.polkadotapp.feature_products_impl.domain.gameReminders.ProductVisibilityTracker
import io.paritytech.polkadotapp.feature_products_impl.presentation.spaBrowser.compose.SpaBrowserScreen
import javax.inject.Inject

@AndroidEntryPoint
class SpaBrowserFragment : BaseComposeFragment<SpaBrowserViewModel>() {
    override val viewModel: SpaBrowserViewModel by viewModels()

    @Inject
    lateinit var productVisibilityTracker: ProductVisibilityTracker

    override fun onResume() {
        super.onResume()
        productVisibilityTracker.setBrowserResumed(true)
    }

    override fun onPause() {
        productVisibilityTracker.setBrowserResumed(false)
        super.onPause()
    }

    @Composable
    override fun Screen() {
        SpaBrowserScreen(viewModel)
    }
}
