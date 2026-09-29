package io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.compose

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.design.components.button.common.PolkadotButtonStyle
import io.paritytech.polkadotapp.design.components.button.default.PolkadotTextButton
import io.paritytech.polkadotapp.design.components.icon.NovaIcon
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.Play
import io.paritytech.polkadotapp.design.components.image.NovaAsyncImage
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.model.VotingCaseUiModel
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.model.VotingOption
import timber.log.Timber
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
internal fun MobRuleCaseCardWidget(
    modifier: Modifier = Modifier,
    caseUiModel: VotingCaseUiModel,
    onVote: (VotingOption) -> Unit,
    onOpenDetail: () -> Unit
) {
    var cardState by remember(caseUiModel.id) { mutableStateOf(if (caseUiModel.isSensitive) CardState.SENSITIVE else CardState.CONTENT) }
    var isExpanded by remember(caseUiModel.id) { mutableStateOf(false) }

    Box(modifier = modifier) {
        CaseCardContentState(
            caseUiModel = caseUiModel,
            isExpanded = isExpanded,
            onToggleExpanded = { isExpanded = !isExpanded },
            onVote = onVote,
            onOpenDetail = onOpenDetail
        )

        val overlayAlpha by animateFloatAsState(
            targetValue = if (cardState == CardState.SENSITIVE) 1f else 0f,
            label = "sensitive_overlay_alpha"
        )
        if (overlayAlpha > 0f) {
            SensitiveContentOverlay(
                onShowEvidence = { cardState = CardState.CONTENT },
                modifier = Modifier
                    .matchParentSize()
                    .alpha(overlayAlpha)
            )
        }
    }
}

@Composable
private fun CaseCardContentState(
    caseUiModel: VotingCaseUiModel,
    isExpanded: Boolean,
    onToggleExpanded: () -> Unit,
    onVote: (VotingOption) -> Unit,
    onOpenDetail: () -> Unit
) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(2f)
                .clickable(onClick = onOpenDetail),
            horizontalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxSize()
                    .clip(RoundedCornerShape(14.dp))
            ) {
                when (caseUiModel) {
                    is VotingCaseUiModel.Photo -> PhotoProofContent(item = caseUiModel)
                    is VotingCaseUiModel.Video -> VideoProofContent(item = caseUiModel)
                    is VotingCaseUiModel.Credentials,
                    is VotingCaseUiModel.UsernameValid -> Unit
                }
            }

            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxSize()
                    .clip(RoundedCornerShape(14.dp))
                    .background(PolkadotTheme.colors.fg.staticWhite),
                contentAlignment = Alignment.Center
            ) {
                caseUiModel.tattooImageLoadable?.let {
                    NovaAsyncImage(
                        model = it,
                        contentScale = ContentScale.Fit,
                        modifier = Modifier.fillMaxSize()
                    )
                }
            }
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(PolkadotTheme.spacings.mediumIncreased)
        ) {
            NovaText(
                text = buildAnnotatedString {
                    append(caseUiModel.title)
                    if (!isExpanded) {
                        append(" ")
                        withStyle(SpanStyle(color = PolkadotTheme.colors.fg.tertiary)) {
                            append(stringResource(RCommon.string.mob_rule_bot_show_more))
                        }
                    }
                },
                style = PolkadotTheme.typography.body.large,
                color = PolkadotTheme.colors.fg.primary,
                modifier = Modifier.clickable(onClick = onToggleExpanded)
            )

            AnimatedVisibility(visible = isExpanded) {
                Column {
                    VerticalSpacer { extraMedium }

                    NovaText(
                        text = caseUiModel.description,
                        style = PolkadotTheme.typography.body.large,
                        color = PolkadotTheme.colors.fg.secondary
                    )

                    VerticalSpacer { extraMedium }

                    NovaText(
                        text = stringResource(RCommon.string.mob_rule_bot_show_less),
                        style = PolkadotTheme.typography.body.large,
                        color = PolkadotTheme.colors.fg.tertiary,
                        modifier = Modifier.clickable(onClick = onToggleExpanded)
                    )
                }
            }
        }
    }
}

@Composable
private fun PhotoProofContent(item: VotingCaseUiModel.Photo) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(PolkadotTheme.colors.fg.staticWhite)
    ) {
        NovaAsyncImage(
            model = item.proofImage,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
            onError = { Timber.e(it.result.throwable, "Failed to load proof image") }
        )
    }
}

@Composable
private fun VideoProofContent(item: VotingCaseUiModel.Video) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(PolkadotTheme.colors.fg.staticWhite)
    ) {
        NovaAsyncImage(
            model = item.proofVideo,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize()
        )

        VideoPlayControl(
            modifier = Modifier.align(Alignment.Center)
        )
    }
}

@Composable
private fun VideoPlayControl(
    modifier: Modifier = Modifier
) {
    PolkadotSurface(
        modifier = modifier,
        shape = PolkadotTheme.shapes.full,
        color = Color(0x73000000)
    ) {
        Box(
            modifier = Modifier.size(48.dp),
            contentAlignment = Alignment.Center
        ) {
            NovaIcon(
                modifier = Modifier.size(24.dp),
                imageVector = NovaIcons.Play,
                tint = PolkadotTheme.colors.fg.primary
            )
        }
    }
}

@Composable
private fun SensitiveContentOverlay(
    onShowEvidence: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(PolkadotTheme.colors.bg.surface.main)
            .padding(PolkadotTheme.spacings.large),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        NovaText(
            text = stringResource(RCommon.string.mob_rule_bot_sensitive_title),
            style = PolkadotTheme.typography.title.large,
            color = PolkadotTheme.colors.fg.primary
        )

        VerticalSpacer { mediumIncreased }

        NovaText(
            text = stringResource(RCommon.string.mob_rule_bot_sensitive_description),
            style = PolkadotTheme.typography.body.large,
            color = PolkadotTheme.colors.fg.secondary
        )

        VerticalSpacer { large }

        PolkadotTextButton(
            text = stringResource(RCommon.string.mob_rule_bot_show_evidence),
            style = PolkadotButtonStyle.secondary(),
            onClick = onShowEvidence
        )
    }
}

private enum class CardState {
    CONTENT, SENSITIVE
}

private val VotingCaseUiModel.tattooImageLoadable
    get() = when (this) {
        is VotingCaseUiModel.Photo -> tattooImage.loadable
        is VotingCaseUiModel.Video -> tattooImage.loadable
        is VotingCaseUiModel.Credentials,
        is VotingCaseUiModel.UsernameValid -> null
    }

private val VotingCaseUiModel.title: String
    @Composable get() = when (this) {
        is VotingCaseUiModel.Photo -> stringResource(RCommon.string.mob_rule_bot_photo_title)
        is VotingCaseUiModel.Video -> stringResource(RCommon.string.mob_rule_bot_video_title)
        is VotingCaseUiModel.Credentials,
        is VotingCaseUiModel.UsernameValid -> ""
    }

private val VotingCaseUiModel.description: String
    @Composable get() = when (this) {
        is VotingCaseUiModel.Photo -> stringResource(RCommon.string.mob_rule_bot_photo_description)
        is VotingCaseUiModel.Video -> stringResource(RCommon.string.mob_rule_bot_video_description)
        is VotingCaseUiModel.Credentials,
        is VotingCaseUiModel.UsernameValid -> ""
    }
