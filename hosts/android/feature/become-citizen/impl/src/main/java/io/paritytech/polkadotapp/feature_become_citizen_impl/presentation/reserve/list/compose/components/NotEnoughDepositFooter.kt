package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.list.compose.components

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.paritytech.polkadotapp.design.colors.LegacyNovaStableColors
import io.paritytech.polkadotapp.design.components.button.common.PolkadotButtonStyle
import io.paritytech.polkadotapp.design.components.button.default.PolkadotTextButton
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_tokens_api.presentation.formatter.LocalKnownTokenFormatter
import io.paritytech.polkadotapp.feature_tokens_api.presentation.formatter.LocalTokenAmountFormatter
import io.paritytech.polkadotapp.feature_tokens_api.presentation.model.AssetDisplay
import io.paritytech.polkadotapp.feature_tokens_api.presentation.model.RoundPrecision
import io.paritytech.polkadotapp.feature_tokens_api.presentation.model.TokenAmountModel
import kotlinx.collections.immutable.persistentMapOf
import io.paritytech.polkadotapp.common.R as RCommon

private const val IconContentId = "ebff3334"
private const val IconPlaceholder = "e83c47ef"

@Composable
fun NotEnoughDepositFooter(
    requiredDeposit: TokenAmountModel,
    assetDisplay: AssetDisplay,
    onDepositAction: () -> Unit,
    depositInProgress: Boolean
) {
    val amountFormatter = LocalTokenAmountFormatter.current
    val formattedAmount = remember(requiredDeposit) {
        amountFormatter.formatTokenAmount(requiredDeposit, RoundPrecision.DEFAULT)
    }

    val tokenFormatter = LocalKnownTokenFormatter.current
    val formattedToken = remember(requiredDeposit) {
        tokenFormatter.appearanceOf(assetDisplay)
    }

    PolkadotSurface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        color = LegacyNovaStableColors.NeutralNeutral900
    ) {
        val amountWithIcon = "$IconPlaceholder $formattedAmount"
        val basicText = stringResource(RCommon.string.tattoo_families_not_enough_deposit_footer, amountWithIcon)

        val inlineContent = remember {
            persistentMapOf(
                IconContentId to InlineTextContent(
                    placeholder = Placeholder(24.sp, 24.sp, PlaceholderVerticalAlign.TextCenter),
                    children = {
                        Image(
                            imageVector = formattedToken.icon,
                            contentDescription = "dot_icon"
                        )
                    }
                )
            )
        }

        val finalText = remember(basicText) {
            buildAnnotatedString {
                val parts = basicText.split(IconPlaceholder)
                for (i in parts.indices) {
                    append(parts[i])
                    if (i < parts.size - 1) {
                        appendInlineContent(IconContentId)
                    }
                }
            }
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(PolkadotTheme.spacings.mediumIncreased)
        ) {
            NovaText(
                text = finalText,
                style = PolkadotTheme.typography.title.large,
                color = PolkadotTheme.colors.fg.primary,
                textAlign = TextAlign.Center,
                inlineContent = inlineContent
            )

            VerticalSpacer { large }

            PolkadotTextButton(
                modifier = Modifier.fillMaxWidth(),
                text = stringResource(RCommon.string.tattoo_families_not_enough_deposit_footer_action, formattedAmount),
                style = PolkadotButtonStyle.primary(),
                loading = depositInProgress,
                onClick = onDepositAction
            )
        }
    }
}
