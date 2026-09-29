package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.list.compose.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.add
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.common.presentation.loading.LoadingState
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.Close
import io.paritytech.polkadotapp.design.components.progress.NovaCircularProgressIndicator
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.components.topbar.PolkadotTopBar
import io.paritytech.polkadotapp.design.components.topbar.TopBarTitleSize
import io.paritytech.polkadotapp.design.components.topbar.rememberTopBarAction
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooFamilyIndex
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.TattooImage
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.models.TattooFamilyUiIdentifier
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.list.models.TattooFamilyUiModel
import kotlinx.collections.immutable.toImmutableList
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
internal fun TattooFamiliesContent(
    isApplied: Boolean,
    familiesState: LoadingState<List<TattooFamilyUiModel>>,
    onFamilyAction: (TattooFamilyUiModel) -> Unit,
    footer: @Composable () -> Unit,
    onBackAction: () -> Unit
) {
    Box(
        modifier = Modifier.fillMaxSize()
    ) {
        var footerHeight by remember { mutableStateOf(0.dp) }

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = WindowInsets(
                bottom = PolkadotTheme.spacings.mediumIncreased + footerHeight,
            ).add(WindowInsets.systemBars).asPaddingValues(),
            verticalArrangement = Arrangement.spacedBy(PolkadotTheme.spacings.large)
        ) {
            item {
                PolkadotTopBar(
                    title = stringResource(
                        if (isApplied) {
                            RCommon.string.tattoo_families_selection_header
                        } else {
                            RCommon.string.tattoo_families_examples_header
                        }
                    ),
                    navigationAction = rememberTopBarAction(onBackAction, NovaIcons.Close),
                    titleSize = TopBarTitleSize.Large,
                )
            }

            when (familiesState) {
                is LoadingState.Loading -> {
                    item {
                        Box(
                            modifier = Modifier.fillMaxWidth(),
                            contentAlignment = Alignment.Center
                        ) {
                            NovaCircularProgressIndicator()
                        }
                    }
                }

                is LoadingState.Error -> { // TODO: ask Andrey how to handle error state for families
                    item {
                        Box(Modifier.fillMaxWidth()) {
                            NovaText("Could not query families: ${familiesState.exception.message}")
                        }
                    }
                }

                is LoadingState.Loaded -> {
                    items(familiesState.data) {
                        FamilyItem(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable(
                                    onClick = { onFamilyAction(it) },
                                    enabled = isApplied
                                ),
                            familyModel = it,
                            canNavigate = isApplied
                        )
                    }
                }
            }
        }

        val density = LocalDensity.current
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .align(Alignment.BottomCenter)
                .padding(PolkadotTheme.spacings.extraMedium)
                .navigationBarsPadding()
                .onSizeChanged {
                    footerHeight = with(density) { it.height.toDp() }
                }
        ) {
            footer()
        }
    }
}

@Preview
@Composable
private fun TattooFamiliesContentPreview() {
    PolkadotTheme {
        TattooFamiliesContent(
            isApplied = true,
            familiesState = LoadingState.Loaded(
                List(3) {
                    TattooFamilyUiModel(
                        identifier = TattooFamilyUiIdentifier.Single(TattooFamilyIndex.ZERO),
                        name = "Tattoo family $it",
                        totalCount = 1234,
                        exampleTattoos = List(3) { TattooImage.Empty }.toImmutableList()
                    )
                }
            ),
            onFamilyAction = {},
            onBackAction = {},
            footer = {}
        )
    }
}
