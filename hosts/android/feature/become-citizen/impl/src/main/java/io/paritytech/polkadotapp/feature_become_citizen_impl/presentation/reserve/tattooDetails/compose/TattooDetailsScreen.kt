@file:OptIn(ExperimentalMaterial3Api::class)

package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.tattooDetails.compose

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.paritytech.polkadotapp.common.presentation.formatters.time.LocalTimeFormatter
import io.paritytech.polkadotapp.common.presentation.formatters.time.TimeFormatter
import io.paritytech.polkadotapp.common.presentation.loading.onLoaded
import io.paritytech.polkadotapp.common.presentation.loading.onLoading
import io.paritytech.polkadotapp.design.components.bottomsheet.NovaModalBottomSheet
import io.paritytech.polkadotapp.design.components.button.default.PolkadotTextButton
import io.paritytech.polkadotapp.design.components.progress.LoadingScreenState
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.topbar.PolkadotTopBar
import io.paritytech.polkadotapp.design.components.topbar.TopBarTitleAlignment
import io.paritytech.polkadotapp.design.components.topbar.rememberTopBarAction
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.TattooImage
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.models.TattooSizeUiModel
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.tattooDetails.TattooDetailsContract
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.tattooDetails.compose.components.TattooCommitmentBottomSheetContent
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.tattooDetails.compose.components.TattooDescription
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.tattooDetails.compose.components.TattooSpecifications
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.tattooDetails.models.EvidenceReviewUiModel
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.tattooDetails.models.TattooMetadataUiModel
import kotlin.time.Duration.Companion.days
import kotlin.time.Duration.Companion.minutes
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun TattooDetailsScreen(contract: TattooDetailsContract) {
    val detailsState by contract.details.collectAsStateWithLifecycle()
    val commitmentState by contract.commitmentState.collectAsStateWithLifecycle()

    detailsState
        .onLoading {
            LoadingScreenState()
        }
        .onLoaded { details ->
            TattooDetailsScreenInternal(
                description = details.metadata,
                size = details.size,
                evidenceReview = details.evidenceReview,
                onProceedAction = contract::onProceedWithThisTattooClicked,
                onBackAction = contract::onBackClicked
            )
        }

    NovaModalBottomSheet(
        isVisible = commitmentState.isVisible,
        onDismissRequest = contract::onTattooReservationDismissed,
        shouldDismissOnClickOutside = !commitmentState.inProgress,
        shouldDismissOnBackPress = !commitmentState.inProgress
    ) {
        TattooCommitmentBottomSheetContent(
            onCancelAction = contract::onTattooReservationDismissed,
            onConfirmAction = contract::onConfirmTattooReservationClicked,
            commitInProgress = commitmentState.inProgress
        )
    }
}

@Composable
private fun TattooDetailsScreenInternal(
    description: TattooMetadataUiModel,
    size: TattooSizeUiModel,
    evidenceReview: EvidenceReviewUiModel?,
    onProceedAction: () -> Unit,
    onBackAction: () -> Unit
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = WindowInsets(
            bottom = PolkadotTheme.spacings.small,
            left = PolkadotTheme.spacings.small,
            right = PolkadotTheme.spacings.small
        ).add(WindowInsets.systemBars).asPaddingValues(),
        verticalArrangement = Arrangement.spacedBy(PolkadotTheme.spacings.small)
    ) {
        item {
            PolkadotTopBar(
                navigationAction = rememberTopBarAction(onBackAction),
                titleAlignment = TopBarTitleAlignment.Center,
            )
        }

        item {
            TattooDescription(description)
        }

        item {
            TattooSpecifications(
                size = size,
                review = evidenceReview
            )
        }

        item {
            PolkadotTextButton(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(PolkadotTheme.spacings.mediumIncreased),
                text = stringResource(RCommon.string.become_citizen_tattoo_proceed),
                onClick = onProceedAction
            )
        }
    }
}

@Preview(device = "spec:width=1080px,height=6500px,dpi=440")
@Composable
private fun TattooDetailsScreenPreview() {
    PolkadotTheme {
        CompositionLocalProvider(
            LocalTimeFormatter provides TimeFormatter.mocked(LocalContext.current)
        ) {
            PolkadotSurface {
                TattooDetailsScreenInternal(
                    description = TattooMetadataUiModel(
                        title = "LemonJelly.ky",
                        description = "Algorithmically generated tattoo inspired by the debut album artwork of the British electronic music duo Lemon Jelly.",
                        image = TattooImage.Empty
                    ),
                    size = TattooSizeUiModel.Variable(25, 50),
                    evidenceReview = EvidenceReviewUiModel(
                        from = 1.minutes,
                        to = 5.days
                    ),
                    onProceedAction = {},
                    onBackAction = {}
                )
            }
        }
    }
}
