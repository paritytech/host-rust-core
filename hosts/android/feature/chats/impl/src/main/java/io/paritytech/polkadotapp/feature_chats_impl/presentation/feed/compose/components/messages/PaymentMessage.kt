package io.paritytech.polkadotapp.feature_chats_impl.presentation.feed.compose.components.messages

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.design.components.icon.NovaIcon
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.ArrowDownward
import io.paritytech.polkadotapp.design.components.icon.vectors.ArrowUpward
import io.paritytech.polkadotapp.design.components.icon.vectors.CheckDouble
import io.paritytech.polkadotapp.design.components.icon.vectors.Close
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatMessageOrigin
import io.paritytech.polkadotapp.feature_chats_api.presentation.model.ChatMessageGrouping
import io.paritytech.polkadotapp.feature_chats_api.presentation.model.ChatMessageSurfaceStyle
import io.paritytech.polkadotapp.feature_chats_api.presentation.model.ChatMessageUiModel
import io.paritytech.polkadotapp.feature_chats_api.presentation.model.MessageAction
import io.paritytech.polkadotapp.feature_chats_api.presentation.model.MessageLayoutInfo
import io.paritytech.polkadotapp.feature_chats_impl.presentation.feed.compose.components.messages.components.FlatMessageTimestamp
import io.paritytech.polkadotapp.feature_chats_impl.presentation.formatter.ChatMessageTimeFormatter
import io.paritytech.polkadotapp.feature_chats_impl.presentation.formatter.LocalChatMessageTimeFormatter
import io.paritytech.polkadotapp.feature_tokens_api.presentation.formatter.LocalTokenAmountFormatter
import io.paritytech.polkadotapp.feature_tokens_api.presentation.formatter.TokenAmountFormatter
import io.paritytech.polkadotapp.feature_tokens_api.presentation.model.RoundPrecision
import io.paritytech.polkadotapp.feature_tokens_api.presentation.model.TokenAmountModel
import kotlinx.collections.immutable.persistentListOf
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun PaymentMessage(
    modifier: Modifier = Modifier,
    message: ChatMessageUiModel.CoinagePayment,
    grouping: ChatMessageGrouping,
    isHighlighted: Boolean,
    username: String,
    canBeReplied: Boolean,
    onMessageAction: (MessageAction) -> Unit,
    onLongPress: (MessageLayoutInfo) -> Unit,
    customBubbleStyle: ChatMessageSurfaceStyle? = null,
) {
    ChatMessageContainer(
        modifier = modifier,
        message = message,
        grouping = grouping,
        isHighlighted = isHighlighted,
        canBeReplied = canBeReplied,
        onMessageAction = onMessageAction,
        onLongPress = onLongPress,
        reactions = message.reactions,
        surfaceStyle = customBubbleStyle ?: ChatMessageSurfaceStyle.default(message.direction),
    ) {
        val isIncoming = message.direction == ChatMessageUiModel.Direction.INCOMING
        val headerText = if (isIncoming) {
            stringResource(RCommon.string.chat_message_payment_incoming, username)
        } else {
            stringResource(RCommon.string.chat_message_payment_outgoing)
        }

        PaymentMessageContent(
            message = message,
            isIncoming = isIncoming,
            headerText = headerText
        )
    }
}

@Composable
private fun PaymentMessageContent(
    message: ChatMessageUiModel.CoinagePayment,
    isIncoming: Boolean,
    headerText: String
) {
    val headerColor: Color
    val amountBoxColor: Color
    val primaryTextColor: Color
    val secondaryTextColor: Color

    if (isIncoming) {
        headerColor = PolkadotTheme.colors.fg.primary
        amountBoxColor = PolkadotTheme.colors.bg.surface.nested
        primaryTextColor = PolkadotTheme.colors.fg.primary
        secondaryTextColor = PolkadotTheme.colors.fg.secondary
    } else {
        headerColor = PolkadotTheme.colors.fg.primaryInverted
        amountBoxColor = PolkadotTheme.colors.bg.surface.nestedInverted
        primaryTextColor = PolkadotTheme.colors.fg.primaryInverted
        secondaryTextColor = PolkadotTheme.colors.fg.secondaryInverted
    }

    val differingAmount = message.differingAmount

    Column(
        modifier = Modifier
            .width(IntrinsicSize.Max)
            .widthIn(max = 200.dp)
    ) {
        VerticalSpacer { extraMedium }

        NovaText(
            modifier = Modifier
                .padding(horizontal = PolkadotTheme.spacings.extraMedium),
            text = headerText,
            style = PolkadotTheme.typography.body.medium,
            color = headerColor
        )

        PolkadotSurface(
            modifier = Modifier
                .fillMaxWidth()
                .padding(
                    vertical = PolkadotTheme.spacings.small,
                    horizontal = PolkadotTheme.spacings.extraMedium
                ),
            shape = PolkadotTheme.shapes.medium,
            color = amountBoxColor
        ) {
            val formatter = LocalTokenAmountFormatter.current

            Column(
                modifier = Modifier
                    .widthIn(min = 154.dp)
                    .padding(PolkadotTheme.spacings.mediumIncreased),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                if (differingAmount != null) {
                    NovaText(
                        text = formatter.formatTokenAmount(message.amount, RoundPrecision.DEFAULT, withSymbol = false),
                        style = PolkadotTheme.typography.body.medium.copy(textDecoration = TextDecoration.LineThrough),
                        color = secondaryTextColor,
                        textAlign = TextAlign.Center
                    )
                    NovaText(
                        text = formatter.formatTokenAmount(differingAmount, RoundPrecision.DEFAULT, withSymbol = false),
                        style = PolkadotTheme.typography.headline.large,
                        color = primaryTextColor,
                        textAlign = TextAlign.Center
                    )
                } else {
                    NovaText(
                        text = formatter.formatTokenAmount(message.amount, RoundPrecision.DEFAULT, withSymbol = false),
                        style = PolkadotTheme.typography.headline.large,
                        color = primaryTextColor,
                        textAlign = TextAlign.Center
                    )
                }

                NovaText(
                    text = formatter.formatToSymbol(message.amount),
                    style = PolkadotTheme.typography.body.medium,
                    color = secondaryTextColor,
                    textAlign = TextAlign.Center
                )
            }
        }

        PaymentStatusIndicator(
            modifier = Modifier.padding(horizontal = PolkadotTheme.spacings.extraMedium),
            status = message.paymentStatus,
            baseStatusColor = secondaryTextColor,
            isIncoming = isIncoming,
            amountsDiffer = differingAmount != null
        )

        VerticalSpacer { tiny }

        Box(
            modifier = Modifier
                .padding(horizontal = PolkadotTheme.spacings.small)
                .align(Alignment.End)
        ) {
            if (isIncoming) {
                FlatMessageTimestamp(
                    modifier = Modifier.align(Alignment.CenterEnd),
                    message = message
                )
            } else {
                FlatMessageTimestamp(message = message)
            }
        }

        VerticalSpacer { small }
    }
}

@Composable
private fun PaymentStatusIndicator(
    modifier: Modifier = Modifier,
    status: ChatMessageUiModel.CoinagePayment.Status,
    baseStatusColor: Color,
    isIncoming: Boolean,
    amountsDiffer: Boolean
) {
    val arrowIcon = if (isIncoming) {
        NovaIcons.ArrowDownward
    } else {
        NovaIcons.ArrowUpward
    }

    val formatter = LocalTokenAmountFormatter.current

    val icon: ImageVector?
    val text: String
    val color: Color

    when {
        amountsDiffer -> {
            icon = null
            text = stringResource(RCommon.string.chat_payment_amount_differs)
            color = PolkadotTheme.colors.fg.warning
        }

        status is ChatMessageUiModel.CoinagePayment.Status.Detecting -> {
            icon = arrowIcon
            text = stringResource(
                if (isIncoming) {
                    RCommon.string.chat_payment_status_detecting_recipient
                } else {
                    RCommon.string.chat_payment_status_detecting_sender
                }
            )
            color = baseStatusColor
        }

        status is ChatMessageUiModel.CoinagePayment.Status.Detected -> {
            icon = arrowIcon
            text = stringResource(
                if (isIncoming) {
                    RCommon.string.chat_payment_status_detected_on_chain_recipient
                } else {
                    RCommon.string.chat_payment_status_detected_on_chain_sender
                }
            )
            color = baseStatusColor
        }

        status is ChatMessageUiModel.CoinagePayment.Status.PartiallyClaimed -> {
            icon = arrowIcon
            text = stringResource(
                RCommon.string.chat_payment_status_partially_claimed,
                formatter.formatTokenAmount(status.claimed, RoundPrecision.DEFAULT)
            )
            color = baseStatusColor
        }

        status is ChatMessageUiModel.CoinagePayment.Status.Transferred -> {
            icon = NovaIcons.CheckDouble
            text = stringResource(RCommon.string.chat_payment_status_claimed)
            color = baseStatusColor
        }

        status is ChatMessageUiModel.CoinagePayment.Status.FailedDetection -> {
            icon = NovaIcons.Close
            text = stringResource(RCommon.string.chat_payment_status_not_detected)
            color = PolkadotTheme.colors.fg.error
        }

        else -> {
            icon = NovaIcons.Close
            text = stringResource(RCommon.string.chat_payment_status_failed)
            color = PolkadotTheme.colors.fg.error
        }
    }

    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(PolkadotTheme.spacings.tiny)
    ) {
        if (icon != null) {
            NovaIcon(
                modifier = Modifier.size(14.dp),
                imageVector = icon,
                tint = color
            )
        }

        NovaText(
            text = text,
            style = PolkadotTheme.typography.body.small,
            color = color
        )
    }
}

@Preview(showBackground = true, backgroundColor = 0xFF000000, heightDp = PREVIEW_HEIGHT)
@Composable
private fun IncomingMessagesPreview() {
    MessagesPreview(direction = ChatMessageUiModel.Direction.INCOMING)
}

@Preview(showBackground = true, backgroundColor = 0xFF000000, heightDp = PREVIEW_HEIGHT)
@Composable
private fun OutcomingMessagesPreview() {
    MessagesPreview(direction = ChatMessageUiModel.Direction.OUTGOING)
}

@Composable
private fun MessagesPreview(direction: ChatMessageUiModel.Direction) {
    PolkadotTheme {
        CompositionLocalProvider(
            LocalChatMessageTimeFormatter provides ChatMessageTimeFormatter.mocked(),
            LocalTokenAmountFormatter provides TokenAmountFormatter.mocked
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                PaymentMessagePreview(
                    direction = direction,
                    paymentStatus = ChatMessageUiModel.CoinagePayment.Status.Detecting,
                )
                PaymentMessagePreview(
                    direction = direction,
                    paymentStatus = ChatMessageUiModel.CoinagePayment.Status.Detected(TokenAmountModel.mock),
                )
                PaymentMessagePreview(
                    direction = direction,
                    paymentStatus = ChatMessageUiModel.CoinagePayment.Status.PartiallyClaimed(
                        TokenAmountModel.mock(value = 500)
                    ),
                )
                PaymentMessagePreview(
                    direction = direction,
                    paymentStatus = ChatMessageUiModel.CoinagePayment.Status.Transferred(TokenAmountModel.mock),
                )
                // Claiming ended short: the amount is struck through and the shortfall called out. Only a
                // finished claim reaches this, which is what keeps it off the screen while a retry is due.
                PaymentMessagePreview(
                    direction = direction,
                    paymentStatus = ChatMessageUiModel.CoinagePayment.Status.Transferred(TokenAmountModel.mock(value = 500)),
                )
                PaymentMessagePreview(
                    direction = direction,
                    paymentStatus = ChatMessageUiModel.CoinagePayment.Status.FailedDetection,
                )
                PaymentMessagePreview(
                    direction = direction,
                    paymentStatus = ChatMessageUiModel.CoinagePayment.Status.FailedTransfer,
                )
                PaymentMessagePreview(
                    direction = direction,
                    paymentStatus = ChatMessageUiModel.CoinagePayment.Status.Detected(TokenAmountModel.mock),
                    deliveryStatus = ChatMessageUiModel.Status.FAILED,
                )
            }
        }
    }
}

@Composable
private fun PaymentMessagePreview(
    direction: ChatMessageUiModel.Direction,
    paymentStatus: ChatMessageUiModel.CoinagePayment.Status,
    deliveryStatus: ChatMessageUiModel.Status = ChatMessageUiModel.Status.SENT
) {
    PaymentMessage(
        modifier = Modifier.fillMaxWidth(),
        message = ChatMessageUiModel.CoinagePayment(
            id = "1",
            direction = direction,
            status = deliveryStatus,
            timestamp = System.currentTimeMillis(),
            amount = TokenAmountModel.mock,
            paymentStatus = paymentStatus,
            origin = ChatMessageOrigin.User,
            reactions = persistentListOf()
        ),
        grouping = ChatMessageGrouping.Standalone,
        isHighlighted = false,
        username = "Glak",
        canBeReplied = true,
        onMessageAction = {},
        onLongPress = {}
    )
}

/** Tall enough for the whole status gallery; the scroll is for the interactive preview. */
private const val PREVIEW_HEIGHT = 1400
