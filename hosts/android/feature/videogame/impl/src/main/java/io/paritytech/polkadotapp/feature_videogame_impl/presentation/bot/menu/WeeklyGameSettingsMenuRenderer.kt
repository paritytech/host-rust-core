package io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.menu

import androidx.compose.animation.AnimatedContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.paritytech.polkadotapp.design.components.bottomsheet.NovaBottomSheetDefaults
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.CustomChatMenuRenderer
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.WeeklyGameBotFooterContract
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.WeeklyGameBotFooterViewModel
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.compose.components.AlertOffsetSelectionContent
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.compose.components.AlertSettingsMainContent
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.theme.NovaPrizesColors

private enum class WeeklyGameSettingsPage {
    MAIN,
    ALERT_SELECTION
}

internal class WeeklyGameSettingsMenuRenderer : CustomChatMenuRenderer {
    @Composable
    override fun DrawMenu(onDismiss: () -> Unit) {
        val contract = hiltViewModel<WeeklyGameBotFooterViewModel>() as WeeklyGameBotFooterContract
        val alertState by contract.alertSettingsState.collectAsStateWithLifecycle()
        var currentPage by remember { mutableStateOf(WeeklyGameSettingsPage.MAIN) }

        AnimatedContent(
            modifier = Modifier
                .fillMaxWidth()
                .background(NovaPrizesColors.bottomSheetBackground),
            targetState = currentPage,
            transitionSpec = { NovaBottomSheetDefaults.PAGE_TRANSITION_SPEC }
        ) { page ->
            when (page) {
                WeeklyGameSettingsPage.MAIN -> {
                    AlertSettingsMainContent(
                        selectedOffset = alertState.selectedOffset,
                        onAlertClick = { currentPage = WeeklyGameSettingsPage.ALERT_SELECTION },
                        onDismiss = onDismiss
                    )
                }

                WeeklyGameSettingsPage.ALERT_SELECTION -> {
                    AlertOffsetSelectionContent(
                        selectedOffset = alertState.selectedOffset,
                        onSelect = { offset ->
                            contract.onAlertOffsetSelect(offset)
                            onDismiss()
                        }
                    )
                }
            }
        }
    }
}
