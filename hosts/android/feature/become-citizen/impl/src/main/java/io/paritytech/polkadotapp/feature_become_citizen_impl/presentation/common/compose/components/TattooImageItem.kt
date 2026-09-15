package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.compose.components

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import io.paritytech.polkadotapp.design.components.image.NovaAsyncImage
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.TattooImage

@Composable
fun TattooImageItem(
    modifier: Modifier = Modifier,
    tattooImage: TattooImage,
    onClick: (() -> Unit)? = null
) {
    PolkadotSurface(
        modifier = modifier,
        shape = PolkadotTheme.shapes.extraLarge,
        color = Color.White,
        onClick = onClick
    ) {
        NovaAsyncImage(
            model = tattooImage.loadable
        )
    }
}
