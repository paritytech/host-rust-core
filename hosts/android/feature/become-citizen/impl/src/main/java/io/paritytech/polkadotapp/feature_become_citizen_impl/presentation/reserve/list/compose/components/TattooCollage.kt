package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.list.compose.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.design.components.spacer.HorizontalSpacer
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.TattooImage
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.compose.components.TattooImageItem
import kotlinx.collections.immutable.ImmutableList

private val HorizontalCollageSpacing = 8.dp
private val InBetweenSpacing = 2.dp

@Composable
internal fun TattoosCollage(
    tattoos: ImmutableList<TattooImage>
) {
    val density = LocalDensity.current
    val windowInfo = LocalWindowInfo.current

    val availableWidth = remember {
        val windowWidth = with(density) { windowInfo.containerSize.width.toDp() }
        windowWidth - HorizontalCollageSpacing * 2 - InBetweenSpacing
    }

    val bigImageSize = availableWidth * 2 / 3
    val smallImageSize = (bigImageSize - InBetweenSpacing) / 2

    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = HorizontalCollageSpacing)
    ) {
        TattooImageItem(
            modifier = Modifier.size(bigImageSize),
            tattooImage = tattoos[0]
        )

        HorizontalSpacer { InBetweenSpacing }

        Column {
            tattoos.getOrNull(1)?.let {
                TattooImageItem(
                    modifier = Modifier.size(smallImageSize),
                    tattooImage = it
                )
            }

            VerticalSpacer { InBetweenSpacing }

            tattoos.getOrNull(2)?.let {
                TattooImageItem(
                    modifier = Modifier.size(smallImageSize),
                    tattooImage = it
                )
            }
        }
    }
}
