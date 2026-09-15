package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.bot.renderers

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.res.stringResource
import dagger.hilt.android.qualifiers.ApplicationContext
import io.paritytech.polkadotapp.common.R
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.toDomain
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.TattooImageLoader
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.model.SelectedTattooContent
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.bot.compose.SelectedTattooWidget
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.CustomChatMessageRenderer
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.MessageDrawingContext
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatMessage
import io.paritytech.polkadotapp.feature_chats_api.presentation.model.ChatMessageUiModel
import io.paritytech.polkadotapp.feature_chats_api.presentation.model.LastMessageUiModel
import javax.inject.Inject

class SelectedTattooRenderer @Inject constructor(
    @param:ApplicationContext private val appContext: Context,
    private val tattooImageLoader: TattooImageLoader
) : CustomChatMessageRenderer<SelectedTattooContent> {
    companion object {
        const val ID = "SelectedTattooRenderer"
    }

    override val id: String = ID

    override val contentSerializer = SelectedTattooContent.serializer()

    @Composable
    override fun DrawMessage(
        message: ChatMessageUiModel.Custom<SelectedTattooContent>,
        context: MessageDrawingContext
    ) {
        message.content.onSuccess { content ->
            val tattooImage = remember(content) {
                tattooImageLoader.getTattooImage(
                    tattooId = content.tattooId.toDomain(),
                    familyId = content.tattooFamilyId.value
                )
            }

            SelectedTattooWidget(content.tattooFamilyName, tattooImage)
        }
    }

    override suspend fun formatNotificationContent(message: ChatMessage.Content.Custom<SelectedTattooContent>) = message.content.map {
        appContext.getString(R.string.chat_bot_tattoo_you_ve_commited_to_tattoo, it.tattooFamilyName)
    }

    @Composable
    override fun formatChatPreview(message: LastMessageUiModel.Custom<SelectedTattooContent>) = message.content.map {
        stringResource(R.string.chat_bot_tattoo_you_ve_commited_to_tattoo, it.tattooFamilyName)
    }
}
