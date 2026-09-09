package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.photo.preview.compose

import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.paritytech.polkadotapp.design.components.button.default.PolkadotTextButton
import io.paritytech.polkadotapp.design.components.image.NovaAsyncImage
import io.paritytech.polkadotapp.design.components.topbar.PolkadotTopBar
import io.paritytech.polkadotapp.design.components.topbar.TopBarTitleAlignment
import io.paritytech.polkadotapp.design.components.topbar.rememberTopBarAction
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.photo.preview.EvidencePhotoPreviewContract
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun EvidencePhotoPreviewScreen(contract: EvidencePhotoPreviewContract) {
    val photoUri by contract.photoUri.collectAsStateWithLifecycle()

    BackHandler {
        contract.back()
    }

    EvidencePhotoPreviewScreenInternal(
        photoUri = photoUri,
        onBack = contract::back,
        onConfirm = contract::confirm,
    )
}

@Composable
private fun EvidencePhotoPreviewScreenInternal(
    photoUri: Uri?,
    onBack: () -> Unit,
    onConfirm: () -> Unit,
) {
    Column(
        modifier = Modifier.fillMaxSize()
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .background(PolkadotTheme.colors.bg.surface.main)
        ) {
            PolkadotTopBar(
                title = stringResource(RCommon.string.evidence_photo_preview_title),
                navigationAction = rememberTopBarAction(onBack),
                titleAlignment = TopBarTitleAlignment.Center,
            )
        }

        NovaAsyncImage(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(1f),
            model = photoUri,
            contentScale = ContentScale.Crop,
            contentDescription = null
        )

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .background(PolkadotTheme.colors.bg.surface.main)
                .navigationBarsPadding()
        ) {
            PolkadotTextButton(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(PolkadotTheme.spacings.large)
                    .align(Alignment.BottomCenter),
                text = stringResource(RCommon.string.common_done),
                onClick = onConfirm
            )
        }
    }
}
