package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.bot.footer

import android.widget.Toast
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.paritytech.polkadotapp.design.components.bottomsheet.NovaModalBottomSheet
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.design.utils.collectAsEffect
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.bot.TattooBotContract
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.bot.compose.TattooBotFooter
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.bot.compose.components.SwitchToDim1ConfirmationContent
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.bot.model.TattooBotQuestion
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatBotData
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.CustomChatFooterRenderer
import io.paritytech.polkadotapp.feature_chats_api.presentation.faq.compose.FaqQuestions
import kotlinx.collections.immutable.toImmutableList
import io.paritytech.polkadotapp.common.R as RCommon

class TattooBotFooterRenderer : CustomChatFooterRenderer {
    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    override fun drawFooter() {
        val contract = hiltViewModel<TattooBotFooterViewModel>() as TattooBotContract
        val state by contract.state.collectAsStateWithLifecycle()
        val dimSwitchMixin = contract.dimSwitchMixin
        val dimSwitchState by dimSwitchMixin.dimSwitchState.collectAsStateWithLifecycle()

        dimSwitchMixin.unavailableEvents.collectAsEffect { context, _ ->
            Toast.makeText(
                context,
                context.getString(RCommon.string.dim_switch_to_dim1_unavailable),
                Toast.LENGTH_SHORT
            ).show()
        }

        Column {
            if (state.showFaq) {
                FaqQuestions(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = PolkadotTheme.spacings.mediumIncreased),
                    botId = ChatBotData.tattoo().id,
                    allQuestions = TattooBotQuestion.entries.toImmutableList()
                )
            }

            VerticalSpacer { mediumIncreased }

            TattooBotFooter(
                state = state,
                onSelectAndReserveTattooClick = contract::proceedToTattooSelection,
                onFilmVideoClick = contract::provideVideoEvidence,
                onTakePhotoClick = contract::providePhotoEvidence,
                onUpgradeUsernameClick = contract::onUpgradeUsernameClick,
                onNavigationToDim2Click = contract::onNavigationToDim2Click,
                onNavigationToMobRuleClick = contract::onNavigationToMobRuleClick,
                onEditClick = dimSwitchMixin::onEditClick
            )
        }

        NovaModalBottomSheet(
            isVisible = dimSwitchState.bottomSheetVisible,
            onDismissRequest = dimSwitchMixin::onSwitchCancel
        ) {
            SwitchToDim1ConfirmationContent(
                onConfirm = dimSwitchMixin::onSwitchConfirm,
                onCancel = dimSwitchMixin::onSwitchCancel,
                inProgress = dimSwitchState.inProgress
            )
        }
    }
}
