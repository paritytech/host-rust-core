package io.paritytech.polkadotapp.feature_wallet_impl.presentation.enterAmount.compose.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import io.paritytech.polkadotapp.design.components.spacer.HorizontalSpacer
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.common.R as RCommon

/**
 * [gainingPrivacy] is named on its own line rather than added to the balance: it is spendable, but only at
 * the cost of the privacy it has earned, so it should not read as money simply sitting there.
 */
@Composable
internal fun EnterAmountBalance(
    modifier: Modifier = Modifier,
    amount: String,
    gainingPrivacy: String?
) {
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            NovaText(
                text = stringResource(RCommon.string.send_enter_amount_max_balance_prefix),
                style = PolkadotTheme.typography.body.large,
                color = PolkadotTheme.colors.fg.secondary
            )

            HorizontalSpacer { tiny }

            NovaText(
                text = amount,
                style = PolkadotTheme.typography.body.large,
                color = PolkadotTheme.colors.fg.primary
            )
        }

        if (gainingPrivacy != null) {
            VerticalSpacer { extraTiny }

            NovaText(
                text = stringResource(RCommon.string.send_enter_amount_privacy_cost_hint, gainingPrivacy),
                style = PolkadotTheme.typography.body.small,
                color = PolkadotTheme.colors.fg.secondary,
                textAlign = TextAlign.Center
            )
        }
    }
}

@Preview
@Composable
private fun EnterAmountBalancePreview() {
    PolkadotTheme {
        EnterAmountBalance(
            amount = "$300",
            gainingPrivacy = "$150"
        )
    }
}

@Preview
@Composable
private fun EnterAmountBalanceNothingExposedPreview() {
    PolkadotTheme {
        EnterAmountBalance(
            amount = "$300",
            gainingPrivacy = null
        )
    }
}
