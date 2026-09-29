package io.paritytech.polkadotapp.feature_upgrade_username_impl.presentation.upgrade

import androidx.compose.runtime.Composable
import androidx.fragment.app.viewModels
import dagger.hilt.android.AndroidEntryPoint
import io.paritytech.polkadotapp.common.presentation.screens.BaseComposeFragment
import io.paritytech.polkadotapp.feature_upgrade_username_impl.presentation.upgrade.compose.UpgradeUsernameScreen

@AndroidEntryPoint
class UpgradeUsernameFragment : BaseComposeFragment<UpgradeUsernameViewModel>() {
    override val viewModel: UpgradeUsernameViewModel by viewModels()

    @Composable
    override fun Screen() = UpgradeUsernameScreen(viewModel)
}
