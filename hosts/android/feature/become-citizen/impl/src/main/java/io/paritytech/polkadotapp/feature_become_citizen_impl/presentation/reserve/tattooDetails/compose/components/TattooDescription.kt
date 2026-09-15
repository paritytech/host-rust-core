package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.tattooDetails.compose.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.tooling.preview.Preview
import io.paritytech.polkadotapp.design.components.image.NovaAsyncImage
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.TattooImage
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.tattooDetails.models.TattooMetadataUiModel

@Composable
fun TattooDescription(
    description: TattooMetadataUiModel
) {
    PolkadotSurface(
        modifier = Modifier.fillMaxWidth(),
        color = PolkadotTheme.colors.bg.surface.container,
        shape = PolkadotTheme.shapes.extraLarge
    ) {
        Column(
            modifier = Modifier.fillMaxWidth()
        ) {
            PolkadotSurface(
                modifier = Modifier
                    .fillMaxWidth()
                    .aspectRatio(1f),
                color = Color.White,
                shape = PolkadotTheme.shapes.extraLarge
            ) {
                NovaAsyncImage(
                    modifier = Modifier.fillMaxSize(),
                    model = description.image.loadable
                )
            }

            Column(
                modifier = Modifier.padding(PolkadotTheme.spacings.mediumIncreased)
            ) {
                NovaText(
                    text = description.title,
                    style = PolkadotTheme.typography.headline.large,
                    color = PolkadotTheme.colors.fg.primary
                )

                VerticalSpacer { small }

                NovaText(
                    text = description.description,
                    style = PolkadotTheme.typography.body.large,
                    color = PolkadotTheme.colors.fg.primary
                )
            }
        }
    }
}

@Preview
@Composable
private fun DescriptionPreview() {
    PolkadotTheme {
        TattooDescription(
            TattooMetadataUiModel(
                title = "LemonJelly.ky",
                description = "Algorithmically generated tattoo inspired by the debut album artwork of the British electronic music duo Lemon Jelly.",
                image = TattooImage.Empty
            )
        )
    }
}
