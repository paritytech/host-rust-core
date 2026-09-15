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
internal fun Location() {
    SpecificationsColumn(
        title = stringResource(RCommon.string.become_citizen_tattoo_location_title)
    ) {
        Image(
            modifier = Modifier.align(Alignment.End),
            painter = painterResource(R.drawable.img_tattoo_placement),
            contentDescription = null
        )

        VerticalSpacer { large }

        NovaText(
            text = stringResource(RCommon.string.become_citizen_tattoo_location_description),
            style = PolkadotTheme.typography.body.large,
            color = PolkadotTheme.colors.fg.primary
        )
    }
}

@Preview
@Composable
private fun LocationPreview() {
    PolkadotTheme {
        Location()
    }
}
