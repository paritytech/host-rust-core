package io.paritytech.polkadotapp.feature_chats_impl.presentation.search

import androidx.compose.runtime.Composable
import androidx.fragment.app.viewModels
import dagger.hilt.android.AndroidEntryPoint
import io.paritytech.polkadotapp.common.presentation.screens.BaseComposeFragment
import io.paritytech.polkadotapp.feature_chats_impl.presentation.search.compose.AddContactScreen

@AndroidEntryPoint
internal class AddContactFragment : BaseComposeFragment<AddContactViewModel>() {
    override val viewModel: AddContactViewModel by viewModels()

    @Composable
    override fun Screen() {
        AddContactScreen(contract = viewModel)
    }
}
