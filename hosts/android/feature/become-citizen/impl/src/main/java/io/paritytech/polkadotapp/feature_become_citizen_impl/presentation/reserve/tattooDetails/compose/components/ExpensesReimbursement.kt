package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.tattooDetails.compose.components

import androidx.compose.foundation.Image
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_become_citizen_impl.R
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun ExpensesReimbursement() {
    SpecificationsColumn(
        title = stringResource(RCommon.string.become_citizen_tattoo_details_reimbursement_title)
    ) {
        Image(
            modifier = Modifier.align(Alignment.CenterHorizontally),
            painter = painterResource(R.drawable.img_reimbursement),
            contentDescription = "reimbursement_image"
        )

        VerticalSpacer { large }

        NovaText(
            text = stringResource(RCommon.string.become_citizen_tattoo_details_reimbursement_description),
            style = PolkadotTheme.typography.body.large,
            color = PolkadotTheme.colors.fg.primary
        )
    }
}

@Preview
@Composable
private fun ExpensesReimbursementPreview() {
    PolkadotTheme {
        ExpensesReimbursement()
    }
}
