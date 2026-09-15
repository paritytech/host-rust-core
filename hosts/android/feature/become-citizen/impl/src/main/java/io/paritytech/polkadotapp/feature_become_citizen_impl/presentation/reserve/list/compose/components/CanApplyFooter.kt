package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.list.compose.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.design.colors.LegacyNovaStableColors
import io.paritytech.polkadotapp.design.components.button.default.PolkadotTextButton
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_tokens_api.presentation.formatter.LocalTokenAmountFormatter
import io.paritytech.polkadotapp.feature_tokens_api.presentation.model.RoundPrecision
import io.paritytech.polkadotapp.feature_tokens_api.presentation.model.TokenAmountModel
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun CanApplyFooter(
    currentBalance: TokenAmountModel,
    onApply: () -> Unit,
    applyInProgress: Boolean
) {
    val amountFormatter = LocalTokenAmountFormatter.current
    val formattedAmount = remember(currentBalance) {
        amountFormatter.formatTokenAmount(currentBalance, RoundPrecision.DEFAULT)
    }

    PolkadotSurface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        color = LegacyNovaStableColors.NeutralNeutral900
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(PolkadotTheme.spacings.large),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            NovaText(
                text = buildAnnotatedString {
                    val fullText = stringResource(
                        RCommon.string.tattoo_families_can_apply_footer_title,
                        formattedAmount
                    )

                    append(fullText)

                    val spanStart = fullText.indexOf(formattedAmount)
                    addStyle(
                        style = SpanStyle(color = PolkadotTheme.colors.fg.primary),
                        start = spanStart,
                        end = spanStart + formattedAmount.length
                    )
                },
                style = PolkadotTheme.typography.body.large,
                color = PolkadotTheme.colors.fg.secondary
            )

            VerticalSpacer { small }

            NovaText(
                text = stringResource(RCommon.string.tattoo_families_can_apply_footer_description),
                style = PolkadotTheme.typography.headline.small,
                color = PolkadotTheme.colors.fg.primary
            )

            VerticalSpacer { extraLarge }

            PolkadotTextButton(
                modifier = Modifier.fillMaxWidth(),
                text = stringResource(RCommon.string.tattoo_families_can_apply_footer_action),
                onClick = onApply,
                loading = applyInProgress
            )
        }
    }
}
