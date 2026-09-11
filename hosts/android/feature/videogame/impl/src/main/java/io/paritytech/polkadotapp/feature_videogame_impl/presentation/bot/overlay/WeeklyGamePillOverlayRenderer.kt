package io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.overlay

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.CustomChatOverlayRenderer

internal class WeeklyGamePillOverlayRenderer : CustomChatOverlayRenderer {
    @Composable
    override fun DrawOverlay() {
        val vm: WeeklyGamePillOverlayViewModel = hiltViewModel()
        val state by vm.pillState.collectAsStateWithLifecycle()
        val shown = state as? VideoGamePillState.Shown ?: return
        GamePillBar(
            state = shown,
            showChevron = true,
            onClick = vm::expand,
        )
    }
}
