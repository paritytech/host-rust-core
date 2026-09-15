package io.paritytech.polkadotapp.feature_videogame_impl.presentation.chatWithPlayers

import androidx.compose.runtime.Composable
import androidx.fragment.app.viewModels
import dagger.hilt.android.AndroidEntryPoint
import io.paritytech.polkadotapp.common.presentation.screens.BaseComposeFragment

@AndroidEntryPoint
class ChatWithPlayersFragment : BaseComposeFragment<ChatWithPlayersViewModel>() {
    override val viewModel: ChatWithPlayersViewModel by viewModels()

    @Composable
    override fun Screen() = ChatWithPlayersScreen(viewModel)
}
