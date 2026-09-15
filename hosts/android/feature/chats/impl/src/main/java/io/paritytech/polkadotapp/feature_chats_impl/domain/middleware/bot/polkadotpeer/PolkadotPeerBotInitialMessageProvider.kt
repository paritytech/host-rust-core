package io.paritytech.polkadotapp.feature_chats_impl.domain.middleware.bot.polkadotpeer

import android.content.Context
import android.graphics.Insets.add
import dagger.hilt.android.qualifiers.ApplicationContext
import io.paritytech.polkadotapp.common.BuildConfig
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatMessage
import io.paritytech.polkadotapp.feature_chats_api.domain.model.createAttachmentFromDrawable
import io.paritytech.polkadotapp.feature_chats_impl.R
import javax.inject.Inject
import io.paritytech.polkadotapp.common.R as RCommon

internal class PolkadotPeerBotInitialMessageProvider @Inject constructor(
    @param:ApplicationContext private val context: Context,
) {
    fun getMessages(): List<ChatMessage.Content> {
        return buildList {
            add(
                ChatMessage.Content.Text(
                    text = context.getString(RCommon.string.chat_peer_join_as_polkadot_peer_message),
                )
            )
            add(
                ChatMessage.Content.RichText(
                    text = context.getString(RCommon.string.chat_peer_option1_weekly_game_message),
                    attachments = listOf(context.createAttachmentFromDrawable(R.drawable.chat_bot_polkadot_peer_weekly_game))
                )
            )
            if (BuildConfig.DIM1_ENABLED) {
                add(
                    ChatMessage.Content.RichText(
                        text = context.getString(RCommon.string.chat_peer_option2_unique_tattoo_message),
                        attachments = listOf(context.createAttachmentFromDrawable(R.drawable.chat_bot_polkadot_peer_unique_tattoos))
                    )
                )
            }
        }
    }
}
