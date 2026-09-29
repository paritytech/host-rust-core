package io.paritytech.polkadotapp.feature_videogame_impl.presentation.renderer

import android.text.format.DateUtils
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.paritytech.polkadotapp.common.domain.model.Timestamp
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.CustomChatHeaderRenderer
import io.paritytech.polkadotapp.feature_chats_api.presentation.ChatContactHeader
import io.paritytech.polkadotapp.common.R as RCommon

internal class GameChatHeaderRenderer : CustomChatHeaderRenderer {
    @Composable
    override fun DrawHeader() {
        val viewModel = hiltViewModel<GameChatHeaderViewModel>()
        val state by viewModel.state.collectAsStateWithLifecycle()

        val username = state.username
        val avatarModel = state.avatarModel

        if (username != null && avatarModel != null) {
            ChatContactHeader(
                username = username,
                avatarModel = avatarModel,
                subtitle = state.gameTimestamp?.let { timestamp ->
                    { GameDateSubtitle(timestamp) }
                }
            )
        }
    }
}

@Composable
private fun GameDateSubtitle(timestamp: Timestamp) {
    val context = LocalContext.current
    val formattedDate = remember(timestamp) {
        DateUtils.formatDateTime(
            context,
            timestamp,
            DateUtils.FORMAT_SHOW_DATE or DateUtils.FORMAT_ABBREV_MONTH
        )
    }

    NovaText(
        text = stringResource(RCommon.string.chat_header_shared_game, formattedDate),
        style = PolkadotTheme.typography.body.medium,
        color = PolkadotTheme.colors.fg.secondary,
        textAlign = TextAlign.Center
    )
}
