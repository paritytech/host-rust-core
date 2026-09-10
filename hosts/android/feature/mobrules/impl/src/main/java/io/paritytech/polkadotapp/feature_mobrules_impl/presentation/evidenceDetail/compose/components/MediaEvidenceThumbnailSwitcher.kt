package io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.compose.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import io.novasama.substrate_sdk_android.extensions.fromHex
import io.paritytech.polkadotapp.design.components.image.NovaAsyncImage
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.TattooImage
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.model.MediaEvidenceThumbnail
import io.paritytech.polkadotapp.tools_ipfs_api.IpfsImageRequest

private val ThumbnailSize = 32.dp

@Composable
internal fun MediaEvidenceThumbnailSwitcher(
    modifier: Modifier = Modifier,
    evidenceHashHex: String,
    tattooImage: TattooImage,
    selectedThumbnail: MediaEvidenceThumbnail,
    onSelectThumbnail: (MediaEvidenceThumbnail) -> Unit,
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(PolkadotTheme.spacings.small, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically
    ) {
        val evidenceImageModel = remember(evidenceHashHex) { IpfsImageRequest(evidenceHashHex.fromHex()) }
        Thumbnail(
            model = evidenceImageModel,
            isSelected = selectedThumbnail == MediaEvidenceThumbnail.EVIDENCE,
            onClick = { onSelectThumbnail(MediaEvidenceThumbnail.EVIDENCE) }
        )

        Thumbnail(
            model = tattooImage.loadable,
            isSelected = selectedThumbnail == MediaEvidenceThumbnail.TATTOO,
            onClick = { onSelectThumbnail(MediaEvidenceThumbnail.TATTOO) }
        )
    }
}

@Composable
private fun Thumbnail(
    model: Any,
    isSelected: Boolean,
    onClick: () -> Unit
) {
    val border = if (isSelected) {
        BorderStroke(PolkadotTheme.borders.medium, PolkadotTheme.colors.fg.primary)
    } else {
        null
    }

    PolkadotSurface(
        shape = PolkadotTheme.shapes.small,
        color = Color.Transparent,
        border = border,
        onClick = onClick,
    ) {
        PolkadotSurface(
            modifier = Modifier
                .padding(PolkadotTheme.borders.medium)
                .size(ThumbnailSize),
            shape = PolkadotTheme.shapes.extraSmall,
            color = PolkadotTheme.colors.fg.staticWhite,
        ) {
            NovaAsyncImage(
                model = model,
                contentScale = ContentScale.Crop,
            )
        }
    }
}
