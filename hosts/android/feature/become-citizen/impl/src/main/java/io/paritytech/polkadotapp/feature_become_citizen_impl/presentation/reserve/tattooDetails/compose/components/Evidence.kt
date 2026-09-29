package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.tattooDetails.compose.components

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_become_citizen_impl.R
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun Evidence() {
    SpecificationsColumn(
        title = stringResource(RCommon.string.become_citizen_tattoo_details_evidence_title)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(PolkadotTheme.spacings.small)
        ) {
            PolkadotSurface(
                modifier = Modifier.weight(1f),
                color = Color(0x0FFFFFFF),
                shape = PolkadotTheme.shapes.large
            ) {
                Image(
                    painter = painterResource(R.drawable.img_poi_video),
                    contentDescription = "evidence_video_image",
                    contentScale = ContentScale.Crop
                )
            }

            PolkadotSurface(
                modifier = Modifier.weight(1f),
                color = Color(0x0FFFFFFF),
                shape = PolkadotTheme.shapes.large
            ) {
                Image(
                    painter = painterResource(R.drawable.img_poi_photo),
                    contentDescription = "evidence_photo_image",
                    contentScale = ContentScale.Crop
                )
            }
        }

        VerticalSpacer { large }

        NovaText(
            text = stringResource(RCommon.string.become_citizen_tattoo_details_evidence_description),
            style = PolkadotTheme.typography.body.large,
            color = PolkadotTheme.colors.fg.primary
        )
    }
}

@Preview
@Composable
private fun EvidencePreview() {
    PolkadotTheme {
        Evidence()
    }
}
