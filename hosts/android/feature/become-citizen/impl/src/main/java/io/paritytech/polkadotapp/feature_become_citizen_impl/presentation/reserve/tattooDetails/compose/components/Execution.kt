package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.tattooDetails.compose.components

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.tattooDetails.compose.icons.TattooMachine
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
internal fun Execution() {
    SpecificationsColumn(
        title = stringResource(RCommon.string.become_citizen_tattoo_details_execution_title)
    ) {
        PolkadotSurface(
            modifier = Modifier.fillMaxWidth(),
            color = Color(0x0FFFFFFF),
            shape = PolkadotTheme.shapes.mediumIncreased
        ) {
            Row(
                modifier = Modifier.padding(PolkadotTheme.spacings.mediumIncreased),
                horizontalArrangement = Arrangement.spacedBy(PolkadotTheme.spacings.mediumIncreased),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Image(
                    imageVector = NovaIcons.TattooMachine,
                    contentDescription = "tattoo_machine_image"
                )

                NovaText(
                    text = stringResource(RCommon.string.become_citizen_tattoo_details_execution_description),
                    style = PolkadotTheme.typography.body.large,
                    color = PolkadotTheme.colors.fg.primary
                )
            }
        }
    }
}

@Preview
@Composable
private fun ExecutionPreview() {
    PolkadotTheme {
        Execution()
    }
}
