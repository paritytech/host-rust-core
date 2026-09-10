package io.paritytech.polkadotapp.feature_videogame_impl.domain.bot.messages.deposit

import android.content.Context
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dagger.hilt.android.qualifiers.ApplicationContext
import io.paritytech.polkadotapp.common.R
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.CustomChatMessageRenderer
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.MessageDrawingContext
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatMessage
import io.paritytech.polkadotapp.feature_chats_api.presentation.model.ChatMessageUiModel
import io.paritytech.polkadotapp.feature_chats_api.presentation.model.LastMessageUiModel
import io.paritytech.polkadotapp.feature_tokens_api.presentation.formatter.TokenAmountFormatter
import io.paritytech.polkadotapp.feature_tokens_api.presentation.model.RoundPrecision
import io.paritytech.polkadotapp.feature_tokens_api.presentation.model.TokenAmountModel
import io.paritytech.polkadotapp.feature_videogame_impl.domain.bot.messages.deposit.model.DepositContent
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.deposit.DepositMessageFormatter
import javax.inject.Inject

class DepositAddedRenderer @Inject constructor(
    @param:ApplicationContext private val context: Context,
    private val tokenFormatter: TokenAmountFormatter,
    private val depositMessageFormatter: DepositMessageFormatter,
) : CustomChatMessageRenderer<DepositContent> {
    companion object {
        const val ID = "DepositRenderer"
    }

    override val id: String = ID

    override val contentSerializer = DepositContent.serializer()

    @Composable
    override fun DrawMessage(
        message: ChatMessageUiModel.Custom<DepositContent>,
        context: MessageDrawingContext
    ) {
        message.content
            .onSuccess { content ->
                val viewModel = bindViewModel(content)
                val amountModel by viewModel.depositFormattedAmount.collectAsStateWithLifecycle()

                amountModel?.let {
                    NovaText(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(PolkadotTheme.spacings.small),
                        text = formatMessage(it),
                        style = PolkadotTheme.typography.body.medium,
                        color = PolkadotTheme.colors.fg.secondary,
                        textAlign = TextAlign.Center
                    )
                }
            }
    }

    override suspend fun formatNotificationContent(message: ChatMessage.Content.Custom<DepositContent>) = message.content.map {
        val amountModel = depositMessageFormatter.formatAmount(it)
        formatMessage(amountModel)
    }

    @Composable
    override fun formatChatPreview(message: LastMessageUiModel.Custom<DepositContent>) = message.content.map { content ->
        val viewModel = bindViewModel(content)
        val amountModel by viewModel.depositFormattedAmount.collectAsStateWithLifecycle()

        amountModel
            ?.let { formatMessage(it) }
            ?: stringResource(R.string.chat_message_deposit_added_empty)
    }

    private fun formatMessage(model: TokenAmountModel): String {
        val amount = tokenFormatter.formatTokenAmount(model, RoundPrecision.DEFAULT)
        return context.getString(R.string.chat_message_deposit_added, amount)
    }

    @Composable
    private fun bindViewModel(depositContent: DepositContent): DepositAddedMessageViewModel {
        return hiltViewModel<DepositAddedMessageViewModel, DepositAddedMessageViewModel.Factory>(
            key = "DepositAddedMessageViewModel",
            creationCallback = { factory -> factory.create(depositContent) }
        )
    }
}
