package io.paritytech.polkadotapp.feature_upgrade_username_api.presentation.bot

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.common.R as RCommon

private val CARD_OUTER_RADIUS = 16.dp
private val PREVIEW_TOP_RADIUS = 14.dp
private val PREVIEW_BOTTOM_RADIUS = 4.dp

private val PILL_HORIZONTAL_PADDING = 22.dp
private val PILL_RADIUS = 48.dp

private val WidgetTitleStyle = TextStyle(
    fontSize = 16.sp,
    lineHeight = 20.sp,
    fontWeight = FontWeight.SemiBold,
)
private val WidgetPillStyle = TextStyle(
    fontSize = 32.sp,
    lineHeight = 38.sp,
    fontWeight = FontWeight.SemiBold,
)
private val WidgetBodyStyle = TextStyle(
    fontSize = 16.sp,
    lineHeight = 20.sp,
    fontWeight = FontWeight.Normal,
)

/**
 * Chat card for the username upgrade. [isUpgraded] selects the claimed copy
 * ("✅ Your new username is") over the available copy ("Get your new username!").
 */
@Composable
fun UpgradeUsernameWidget(
    modifier: Modifier = Modifier,
    usernameWithoutSuffix: String,
    isUpgraded: Boolean
) {
    val titleRes = if (isUpgraded) {
        RCommon.string.upgrade_username_widget_title_upgraded
    } else {
        RCommon.string.upgrade_username_widget_title
    }
    val subtitleRes = if (isUpgraded) {
        RCommon.string.upgrade_username_congrats_subtitle
    } else {
        RCommon.string.upgrade_username_any_other_username
    }
    val descriptionRes = if (isUpgraded) {
        RCommon.string.upgrade_username_keep_playing_description
    } else {
        RCommon.string.upgrade_username_description_placeholder
    }

    Column(modifier = modifier) {
        if (!isUpgraded) {
            VerticalSpacer { small }

            NovaText(
                modifier = Modifier.fillMaxWidth(),
                textAlign = TextAlign.Center,
                text = buildMemberBannerText(),
                color = UpgradeUsernameColors.primaryText,
                style = PolkadotTheme.typography.body.medium
            )

            VerticalSpacer { mediumIncreased }
        }

        PolkadotSurface(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(CARD_OUTER_RADIUS),
            color = UpgradeUsernameColors.cardBg,
            border = BorderStroke(PolkadotTheme.borders.default, UpgradeUsernameColors.cardBorder),
        ) {
            Column(modifier = Modifier.fillMaxWidth()) {
                UpgradePreviewBlock(
                    usernameWithoutSuffix = usernameWithoutSuffix,
                    titleRes = titleRes,
                    subtitleRes = subtitleRes,
                )

                VerticalSpacer { small }

                NovaText(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = PolkadotTheme.spacings.mediumIncreased),
                    style = WidgetBodyStyle,
                    color = UpgradeUsernameColors.primaryText,
                    textAlign = TextAlign.Start,
                    text = stringResource(descriptionRes)
                )

                VerticalSpacer { small }
            }
        }
    }
}

// Mute only the text; a translucent color applied to the whole string would dim the emoji glyph.
private fun mutedTitleKeepingEmoji(text: String): AnnotatedString {
    val firstLetter = text.indexOfFirst { it.isLetter() }
    return buildAnnotatedString {
        if (firstLetter > 0) append(text.substring(0, firstLetter))
        withStyle(SpanStyle(color = UpgradeUsernameColors.mutedText)) {
            append(text.substring(firstLetter.coerceAtLeast(0)))
        }
    }
}

@Composable
private fun buildMemberBannerText() = buildAnnotatedString {
    withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) {
        append(stringResource(RCommon.string.chat_you_are_member_bold))
    }
    append(" ")
    append(stringResource(RCommon.string.chat_you_are_member_rest))
}

@Composable
private fun UpgradePreviewBlock(
    usernameWithoutSuffix: String,
    titleRes: Int,
    subtitleRes: Int,
) {
    PolkadotSurface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(
            topStart = PREVIEW_TOP_RADIUS,
            topEnd = PREVIEW_TOP_RADIUS,
            bottomStart = PREVIEW_BOTTOM_RADIUS,
            bottomEnd = PREVIEW_BOTTOM_RADIUS,
        ),
        color = UpgradeUsernameColors.previewBlockBg,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(
                    horizontal = PolkadotTheme.spacings.mediumIncreased,
                    vertical = PolkadotTheme.spacings.large,
                ),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            NovaText(
                style = WidgetTitleStyle,
                color = UpgradeUsernameColors.primaryText,
                textAlign = TextAlign.Center,
                text = mutedTitleKeepingEmoji(stringResource(titleRes))
            )

            VerticalSpacer { mediumIncreased }

            PolkadotSurface(
                shape = RoundedCornerShape(PILL_RADIUS),
                color = UpgradeUsernameColors.pillBackground,
                border = BorderStroke(PolkadotTheme.borders.medium, UpgradeUsernameColors.pillBorder)
            ) {
                NovaText(
                    modifier = Modifier.padding(
                        horizontal = PILL_HORIZONTAL_PADDING,
                        vertical = PolkadotTheme.spacings.extraMedium,
                    ),
                    style = WidgetPillStyle,
                    color = UpgradeUsernameColors.primaryText,
                    text = usernameWithoutSuffix,
                )
            }

            VerticalSpacer { mediumIncreased }

            NovaText(
                style = WidgetBodyStyle,
                color = UpgradeUsernameColors.mutedText,
                textAlign = TextAlign.Center,
                text = stringResource(subtitleRes)
            )
        }
    }
}

@Preview
@Composable
private fun UpgradeUsernameWidgetUpgradedPreview() {
    PolkadotTheme {
        UpgradeUsernameWidget(
            usernameWithoutSuffix = "bongo",
            isUpgraded = true
        )
    }
}

@Preview
@Composable
private fun UpgradeUsernameWidgetNotUpgradedPreview() {
    PolkadotTheme {
        UpgradeUsernameWidget(
            usernameWithoutSuffix = "bingbong",
            isUpgraded = false
        )
    }
}
