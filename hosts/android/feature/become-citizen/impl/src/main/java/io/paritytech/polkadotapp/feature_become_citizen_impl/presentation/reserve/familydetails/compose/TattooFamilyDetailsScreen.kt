package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.familydetails.compose

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import io.paritytech.polkadotapp.common.R
import io.paritytech.polkadotapp.common.presentation.loading.LoadingState
import io.paritytech.polkadotapp.design.components.error.DefaultErrorState
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.Close
import io.paritytech.polkadotapp.design.components.progress.LoadingScreenState
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.components.topbar.PolkadotTopBar
import io.paritytech.polkadotapp.design.components.topbar.TopBarTitleSize
import io.paritytech.polkadotapp.design.components.topbar.rememberTopBarAction
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.compose.components.TattooImageItem
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.familydetails.TattooFamilyDetailsContract
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.familydetails.models.TattooFamilyDetailsPreviewUiModel
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.familydetails.models.TattooFamilyDetailsUiModel
import kotlinx.collections.immutable.persistentListOf

@Composable
fun TattooFamilyDetailsScreen(contract: TattooFamilyDetailsContract) {
    val familyDetailsState = contract.familyDetails.collectAsState().value

    PolkadotSurface {
        when (familyDetailsState) {
            is LoadingState.Loading -> LoadingScreenState()

            is LoadingState.Error -> DefaultErrorState(stringResource(R.string.tattoo_family_details_error))

            is LoadingState.Loaded<TattooFamilyDetailsUiModel> -> TattooFamilyDetailsScreenInternal(
                uiModel = familyDetailsState.data,
                onBackClick = contract::onBackClick,
                onPreviewClick = contract::onPreviewClick
            )
        }
    }
}

@Composable
fun TattooFamilyDetailsScreenInternal(
    uiModel: TattooFamilyDetailsUiModel,
    onBackClick: () -> Unit,
    onPreviewClick: (TattooFamilyDetailsPreviewUiModel) -> Unit
) {
    PolkadotSurface {
        val gridState = rememberLazyGridState()

        LazyVerticalGrid(
            columns = GridCells.Fixed(2),
            state = gridState,
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(horizontal = PolkadotTheme.spacings.small),
            verticalArrangement = Arrangement.spacedBy(PolkadotTheme.spacings.small),
            horizontalArrangement = Arrangement.spacedBy(PolkadotTheme.spacings.small),
        ) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                val title = when (uiModel) {
                    is TattooFamilyDetailsUiModel.Personal -> stringResource(R.string.tattoo_families_personal_tattoos_title)
                    is TattooFamilyDetailsUiModel.Designed -> uiModel.title
                }

                val description = when (uiModel) {
                    is TattooFamilyDetailsUiModel.Personal -> stringResource(R.string.tattoo_families_personal_tattoos_description)
                    is TattooFamilyDetailsUiModel.Designed -> uiModel.description
                }

                TattooFamilyDetailsHeader(
                    title = title,
                    description = description,
                    onBackClick = onBackClick
                )
            }

            items(items = uiModel.previews) {
                TattooImageItem(
                    modifier = Modifier
                        .fillMaxWidth()
                        .aspectRatio(1f),
                    tattooImage = it.image,
                    onClick = { onPreviewClick(it) }
                )
            }
        }
    }
}

@Composable
private fun TattooFamilyDetailsHeader(
    title: String,
    description: String,
    onBackClick: () -> Unit
) {
    Column(
        modifier = Modifier
            .systemBarsPadding()
            .fillMaxSize()
    ) {
        PolkadotTopBar(
            title = title,
            navigationAction = rememberTopBarAction(
                action = onBackClick,
                icon = NovaIcons.Close
            ),
            titleSize = TopBarTitleSize.Large,
        )

        VerticalSpacer { mediumIncreased }

        NovaText(
            text = description,
            color = PolkadotTheme.colors.fg.primary,
            style = PolkadotTheme.typography.body.large,
            modifier = Modifier.padding(horizontal = PolkadotTheme.spacings.large)
        )
    }
}

@Preview
@Composable
fun TattooFamilyDetailsScreenInternalPreview() {
    PolkadotTheme {
        TattooFamilyDetailsScreenInternal(
            uiModel = TattooFamilyDetailsUiModel.Personal(persistentListOf()),
            onBackClick = {},
            onPreviewClick = {}
        )
    }
}
