package io.paritytech.polkadotapp.feature_chats_impl.presentation.polkadotpeerbot.compose

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import io.paritytech.polkadotapp.common.R
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_chats_api.presentation.common.ChatFooterNavigationButton
import io.paritytech.polkadotapp.feature_chats_impl.presentation.ChatTestTags
import io.paritytech.polkadotapp.feature_chats_impl.presentation.feed.compose.components.ChatFooterLabel
import io.paritytech.polkadotapp.feature_chats_impl.presentation.polkadotpeerbot.models.PolkadotPeerBotFooterState

@Composable
fun PolkadotPeerBotFooter(
    state: PolkadotPeerBotFooterState,
    onNavigationToDim1Click: () -> Unit,
    onNavigationToDim2Click: () -> Unit
) {
    Column {
        ChatFooterLabel(stringResource(R.string.chat_dim_navigation_buttons_title))

        VerticalSpacer { small }

        Column(
            Modifier.padding(horizontal = PolkadotTheme.spacings.mediumIncreased)
        ) {
            if (state.showDim1NavigationButton) {
                ChatFooterNavigationButton(
                    title = stringResource(R.string.chat_dim1_navigation_button_title),
                    description = stringResource(R.string.chat_dim1_navigation_button_description),
                    actionName = stringResource(R.string.common_open),
                    onClick = onNavigationToDim1Click
                )
            }

            if (state.showDim2NavigationButton) {
                VerticalSpacer { small }

                ChatFooterNavigationButton(
                    modifier = Modifier.testTag(ChatTestTags.CHAT_WEEKLY_GAME_OPEN_BUTTON),
                    title = stringResource(R.string.chat_dim2_navigation_button_title),
                    description = stringResource(R.string.chat_dim2_navigation_button_description),
                    actionName = stringResource(R.string.common_open),
                    onClick = onNavigationToDim2Click
                )
            }

            VerticalSpacer { small }
        }
    }
}
