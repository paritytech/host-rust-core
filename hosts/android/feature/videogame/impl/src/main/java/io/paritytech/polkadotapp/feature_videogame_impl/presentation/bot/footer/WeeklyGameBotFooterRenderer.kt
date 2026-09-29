package io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.footer

import android.widget.Toast
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.paritytech.polkadotapp.design.components.bottomsheet.NovaModalBottomSheet
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.utils.collectAsEffect
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.CustomChatFooterRenderer
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.WeeklyGameBotFooterContract
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.WeeklyGameBotFooterViewModel
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.compose.WeeklyGameBotFooter
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.compose.components.SwitchToDim2ConfirmationContent
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.compose.components.WeeklyGameDepositBottomSheetContent
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.models.UpcomingGameUiState
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.models.WeeklyGameFooterState
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.overlay.GamePillBar
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.overlay.VideoGamePillState
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.overlay.WeeklyGamePillInlineViewModel
import io.paritytech.polkadotapp.common.R as RCommon

class WeeklyGameBotFooterRenderer : CustomChatFooterRenderer {
    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    override fun drawFooter() {
        val contract = hiltViewModel<WeeklyGameBotFooterViewModel>() as WeeklyGameBotFooterContract

        val depositState by contract.depositState.collectAsStateWithLifecycle()
        val uiState by contract.uiState.collectAsStateWithLifecycle()
        val footerContent by contract.footerState.collectAsStateWithLifecycle()
        val dimSwitchMixin = contract.dimSwitchMixin
        val dimSwitchState by dimSwitchMixin.dimSwitchState.collectAsStateWithLifecycle()

        dimSwitchMixin.unavailableEvents.collectAsEffect { context, _ ->
            Toast.makeText(
                context,
                context.getString(RCommon.string.dim_switch_to_dim2_unavailable),
                Toast.LENGTH_SHORT
            ).show()
        }

        // Composable-lifecycle signal — published while this widget is actually on screen,
        // not just while the VM is alive in the back stack.
        val widgetVisible = uiState.upcomingGameUiState != null &&
            uiState.upcomingGameUiState !is UpcomingGameUiState.Starting &&
            footerContent == WeeklyGameFooterState.Normal
        DisposableEffect(widgetVisible) {
            contract.setUpcomingWidgetVisible(widgetVisible)
            onDispose { contract.setUpcomingWidgetVisible(false) }
        }

        WeeklyGameBotFooter(
            footerContent = footerContent,
            uiState = uiState,
            onRegister = contract::register,
            onStartPlaying = contract::startGame,
            onUpgradeUsernameClick = contract::onUpgradeUsernameClick,
            onAddToCalendar = contract::addToCalendar,
            onEditClick = dimSwitchMixin::onEditClick,
            pillSlot = { InlinePillSection(onVisibilityChange = contract::setInlinePillVisible) },
        )

        NovaModalBottomSheet(
            isVisible = depositState.isVisible,
            onDismissRequest = { contract.cancelDeposit() }
        ) {
            depositState.requiredAmount?.let {
                WeeklyGameDepositBottomSheetContent(
                    requiredAmount = it,
                    onDeposit = contract::deposit,
                    inProgress = depositState.inProgress
                )
            }
        }

        NovaModalBottomSheet(
            isVisible = dimSwitchState.bottomSheetVisible,
            onDismissRequest = dimSwitchMixin::onSwitchCancel
        ) {
            SwitchToDim2ConfirmationContent(
                onConfirm = dimSwitchMixin::onSwitchConfirm,
                onCancel = dimSwitchMixin::onSwitchCancel,
                inProgress = dimSwitchState.inProgress
            )
        }
    }
}

@Composable
private fun InlinePillSection(onVisibilityChange: (Boolean) -> Unit) {
    val pillVm: WeeklyGamePillInlineViewModel = hiltViewModel()
    val state by pillVm.pillState.collectAsStateWithLifecycle()
    val shown = state as? VideoGamePillState.Shown

    DisposableEffect(shown != null) {
        onVisibilityChange(shown != null)
        onDispose { onVisibilityChange(false) }
    }

    if (shown != null) {
        VerticalSpacer { small }
        Box(
            modifier = Modifier.fillMaxWidth(),
            contentAlignment = Alignment.Center,
        ) {
            GamePillBar(
                state = shown,
                showChevron = true,
                onClick = pillVm::expand,
            )
        }
    }
}
