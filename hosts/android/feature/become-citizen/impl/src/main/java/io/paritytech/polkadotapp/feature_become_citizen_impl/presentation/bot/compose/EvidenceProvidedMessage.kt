package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.bot.compose

import android.net.Uri
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.media3.ui.compose.ContentFrame
import io.paritytech.polkadotapp.common.presentation.compose.video.VideoPlayerControlsContainer
import io.paritytech.polkadotapp.common.presentation.compose.video.rememberExoPlayer
import io.paritytech.polkadotapp.common.presentation.compose.video.toProgressiveMediaSource
import io.paritytech.polkadotapp.design.colors.LegacyNovaStableColors
import io.paritytech.polkadotapp.design.components.icon.NovaIcon
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.CheckCircleOutlined
import io.paritytech.polkadotapp.design.components.icon.vectors.Info
import io.paritytech.polkadotapp.design.components.icon.vectors.PollOutlined
import io.paritytech.polkadotapp.design.components.icon.vectors.Upload
import io.paritytech.polkadotapp.design.components.image.NovaAsyncImage
import io.paritytech.polkadotapp.design.components.spacer.HorizontalSpacer
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.EvidenceType
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.bot.renderers.evidence.models.EvidenceProvidedMessageUiModel
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.bot.renderers.evidence.models.EvidenceProvidingState
import io.paritytech.polkadotapp.feature_chats_api.presentation.common.getMaxMessageWidth
import io.paritytech.polkadotapp.feature_tokens_api.presentation.formatter.LocalTokenAmountFormatter
import kotlinx.collections.immutable.persistentMapOf
import io.paritytech.polkadotapp.common.R as RCommon

private const val StateIconInlineId = "34ecd227-cb00-4712-bc9c-191b5e1a94f2"

@Composable
fun EvidenceProvidedMessageContent(
    message: EvidenceProvidedMessageUiModel
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(
                horizontal = PolkadotTheme.spacings.mediumIncreased,
                vertical = PolkadotTheme.spacings.small
            )
    ) {
        PolkadotSurface(
            modifier = Modifier
                .align(Alignment.End)
                .size(getMaxMessageWidth()),
            shape = PolkadotTheme.shapes.mediumIncreased
        ) {
            Box(modifier = Modifier.fillMaxSize()) {
                when (message.evidenceType) {
                    EvidenceType.PHOTO -> PhotoEvidence(message.uri)
                    EvidenceType.VIDEO -> VideoEvidence(message.uri)
                }

                SmallState(
                    modifier = Modifier
                        .align(Alignment.TopStart)
                        .padding(PolkadotTheme.spacings.small),
                    state = message.providingState
                )
            }
        }

        message.providingState?.let {
            VerticalSpacer { mediumIncreased }
            FullStateDescription(
                type = message.evidenceType,
                state = it
            )
        }

        MessageFooter(message)
    }
}

@Composable
private fun MessageFooter(message: EvidenceProvidedMessageUiModel) {
    when (message.evidenceType) {
        EvidenceType.VIDEO -> {
            VerticalSpacer { mediumIncreased }

            NovaText(
                modifier = Modifier.fillMaxWidth(),
                text = stringResource(RCommon.string.evidence_provided_video_message_footer),
                style = PolkadotTheme.typography.body.medium,
                color = PolkadotTheme.colors.fg.secondary,
                textAlign = TextAlign.Center
            )
        }

        EvidenceType.PHOTO -> Unit
    }
}

@Composable
private fun PhotoEvidence(uri: Uri?) {
    NovaAsyncImage(
        modifier = Modifier.fillMaxSize(),
        model = uri,
        contentScale = ContentScale.Crop
    )
}

@Composable
private fun VideoEvidence(uri: Uri?) {
    val context = LocalContext.current
    val mediaSource = remember(uri) {
        uri?.toProgressiveMediaSource(context)
    }
    val player = rememberExoPlayer(mediaSource = mediaSource, playWhenReady = false)

    VideoPlayerControlsContainer(
        modifier = Modifier.fillMaxSize(),
        player = player
    ) {
        ContentFrame(
            modifier = Modifier
                .fillMaxSize()
                .clipToBounds(),
            player = player,
            contentScale = ContentScale.Crop
        )
    }
}

@Composable
private fun SmallState(
    modifier: Modifier = Modifier,
    state: EvidenceProvidingState?
) {
    when (state) {
        is EvidenceProvidingState.Uploading -> {
            UploadingStateWidget(
                modifier = modifier,
                text = stringResource(
                    RCommon.string.evidence_provided_status_uploading_progress,
                    LocalTokenAmountFormatter.current.formatPercent(state.progress)
                )
            )
        }

        is EvidenceProvidingState.Queued -> {
            UploadingStateWidget(
                modifier = modifier,
                text = stringResource(RCommon.string.evidence_provided_status_queued)
            )
        }

        else -> Unit
    }
}

@Composable
private fun UploadingStateWidget(modifier: Modifier, text: String) {
    PolkadotSurface(
        modifier = modifier,
        shape = PolkadotTheme.shapes.full,
        color = Color(0x73000000)
    ) {
        Row(
            modifier = Modifier
                .padding(
                    horizontal = PolkadotTheme.spacings.small,
                    vertical = PolkadotTheme.spacings.tiny
                ),
            verticalAlignment = Alignment.CenterVertically
        ) {
            NovaIcon(
                modifier = Modifier.size(14.dp),
                imageVector = NovaIcons.Upload,
                tint = PolkadotTheme.colors.fg.primary
            )

            HorizontalSpacer { tiny }

            NovaText(
                text = text,
                style = PolkadotTheme.typography.body.small,
                color = PolkadotTheme.colors.fg.primary
            )
        }
    }
}

@Composable
private fun FullStateDescription(
    type: EvidenceType,
    state: EvidenceProvidingState
) {
    val icon: ImageVector
    val color: Color
    val statusText: String

    when (state) {
        is EvidenceProvidingState.Queued -> {
            icon = NovaIcons.Upload
            color = PolkadotTheme.colors.fg.secondary
            statusText = stringResource(RCommon.string.evidence_provided_status_queued)
        }

        is EvidenceProvidingState.Uploading -> {
            icon = NovaIcons.Upload
            color = PolkadotTheme.colors.fg.secondary
            statusText = stringResource(RCommon.string.evidence_provided_status_uploading)
        }

        is EvidenceProvidingState.InReview -> {
            icon = NovaIcons.PollOutlined
            color = LegacyNovaStableColors.AmberAmber500
            statusText = stringResource(RCommon.string.evidence_provided_status_in_review)
        }

        is EvidenceProvidingState.Approved -> {
            icon = NovaIcons.CheckCircleOutlined
            color = PolkadotTheme.colors.fg.success
            statusText = stringResource(RCommon.string.evidence_provided_status_approved)
        }

        is EvidenceProvidingState.Failed -> {
            icon = NovaIcons.Info
            color = PolkadotTheme.colors.fg.error
            statusText = stringResource(RCommon.string.evidence_provided_status_failed)
        }
    }

    val inlineContent = remember(state) {
        persistentMapOf(
            StateIconInlineId to InlineTextContent(
                placeholder = Placeholder(14.sp, 14.sp, PlaceholderVerticalAlign.TextCenter),
                children = {
                    NovaIcon(
                        imageVector = icon,
                        contentDescription = "state_icon",
                        tint = color
                    )
                }
            )
        )
    }

    NovaText(
        modifier = Modifier.fillMaxWidth(),
        text = buildAnnotatedString {
            val mainText = stringResource(
                when (type) {
                    EvidenceType.PHOTO -> RCommon.string.evidence_provided_photo_message_status
                    EvidenceType.VIDEO -> RCommon.string.evidence_provided_video_message_status
                }
            )

            append(mainText)
            append(" ")
            appendInlineContent(StateIconInlineId)

            withStyle(SpanStyle(color = color)) {
                append(" ")
                append(statusText)
            }
        },
        inlineContent = inlineContent,
        style = PolkadotTheme.typography.body.medium,
        color = PolkadotTheme.colors.fg.secondary,
        textAlign = TextAlign.Center
    )
}
