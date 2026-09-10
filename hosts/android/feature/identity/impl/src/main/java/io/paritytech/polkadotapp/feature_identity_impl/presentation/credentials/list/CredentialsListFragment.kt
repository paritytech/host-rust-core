package io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.list

import androidx.compose.runtime.Composable
import androidx.fragment.app.viewModels
import io.paritytech.polkadotapp.common.presentation.screens.BaseComposeFragment
import io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.list.compose.CredentialsListScreen

class CredentialsListFragment : BaseComposeFragment<CredentialsListViewModel>() {
    override val viewModel: CredentialsListViewModel by viewModels()

    @Composable
    override fun Screen() = CredentialsListScreen(viewModel)
}
