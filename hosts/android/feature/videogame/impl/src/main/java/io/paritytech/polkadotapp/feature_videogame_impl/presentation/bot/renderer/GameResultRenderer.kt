package io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.renderer

import android.content.Context
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.CustomChatMessageRenderer
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.MessageDrawingContext
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatMessage
import io.paritytech.polkadotapp.feature_chats_api.presentation.model.ChatMessageUiModel
import io.paritytech.polkadotapp.feature_chats_api.presentation.model.LastMessageUiModel
import io.paritytech.polkadotapp.feature_videogame_impl.domain.bot.messages.gameResult.model.PastGameContent
import io.paritytech.polkadotapp.feature_videogame_impl.domain.bot.messages.gameResult.model.PastGameOutcome
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.compose.ChatWithPlayers
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.compose.PastGameCard
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.compose.getSecondaryText
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.compose.getTitleRes
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.gameResult.GameResultContract
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.gameResult.GameResultViewModel
import kotlinx.collections.immutable.toImmutableList
import javax.inject.Inject

class GameResultRenderer @Inject constructor(
    @param:ApplicationContext private val appContext: Context
) : CustomChatMessageRenderer<PastGameContent> {
    companion object {
        const val ID = "GameResultRenderer"
    }

    override val id: String = ID

    override val contentSerializer = PastGameContent.serializer()

    @Composable
    override fun DrawMessage(
        message: ChatMessageUiModel.Custom<PastGameContent>,
        context: MessageDrawingContext
    ) {
        message.content.onSuccess { content ->
            val contract = hiltViewModel<GameResultViewModel, GameResultViewModel.Factory>(
                key = message.id,
                creationCallback = { it.create(content.gameIndex.value) }
            ) as GameResultContract

            Box(
                modifier = context.messageModifier
            ) {
                Column(modifier = Modifier.align(Alignment.Center)) {
                    PastGameCard(outcome = content.outcome, timestamp = content.timestamp)

                    if (content.outcome is PastGameOutcome.Success) {
                        VerticalSpacer { extraSmall }

                        val playerAvatarPaths = remember(content.playerAvatarPaths) {
                            content.playerAvatarPaths.toImmutableList()
                        }

                        ChatWithPlayers(
                            playerAvatarPaths = playerAvatarPaths,
                            onClick = { contract.onChatWithPlayersClick() }
                        )
                    }
                }
            }
        }
    }

    override suspend fun formatNotificationContent(message: ChatMessage.Content.Custom<PastGameContent>) = message.content.map {
        appContext.getString(it.outcome.getTitleRes())
    }

    @Composable
    override fun formatChatPreview(message: LastMessageUiModel.Custom<PastGameContent>) = message.content.map {
        val title = stringResource(it.outcome.getTitleRes())
        val subtitle = getSecondaryText(it.outcome)

        "$title. $subtitle"
    }
}
