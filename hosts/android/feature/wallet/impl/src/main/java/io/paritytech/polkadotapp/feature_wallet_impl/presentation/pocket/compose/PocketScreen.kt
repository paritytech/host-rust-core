package io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.SharedTransitionLayout
import androidx.compose.animation.core.Transition
import androidx.compose.animation.core.updateTransition
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.layout
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.paritytech.polkadotapp.common.presentation.loading.LoadingState
import io.paritytech.polkadotapp.design.components.navigationbar.LocalAppNavigationBarInsets
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.topbar.PolkadotTopBar
import io.paritytech.polkadotapp.design.components.topbar.TopBarTitleSize
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_tokens_api.presentation.formatter.LocalTokenAmountFormatter
import io.paritytech.polkadotapp.feature_tokens_api.presentation.formatter.TokenAmountFormatter
import io.paritytech.polkadotapp.feature_tokens_api.presentation.model.TokenAmountModel
import io.paritytech.polkadotapp.feature_wallet_impl.domain.model.PocketRank
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.PocketViewModel
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.animation.LocalCardTilt
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.animation.rememberCardTilt
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.*
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.digitalDollar.DigitalDollarCard
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.digitalDollar.DigitalDollarCardDetails
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.id.IdCard
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.id.IdCardDetails
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.models.PocketCardUiModel
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.models.PocketScreenState
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.persistentListOf
import io.paritytech.polkadotapp.common.R as RCommon

private val CollectiblesSketchbookPeek = 80.dp

@Composable
fun PocketScreen() {
    val viewModel = hiltViewModel<PocketViewModel>()

    val screenState by viewModel.state.collectAsStateWithLifecycle()
    val cards by viewModel.cards.collectAsStateWithLifecycle()

    PocketScreenInternal(
        screenState = screenState,
        cards = cards,
        onCardSelected = viewModel::selectCard,
        onCardDismissed = viewModel::dismissCard,
        onShareId = viewModel::onShareId,
        onSketchbookSelected = viewModel::showCollectiblesSketchbook,
        onSketchbookDismissed = viewModel::hideCollectiblesSketchbook,
        onOpenCollectibles = viewModel::openCollectibles
    )
}

@Composable
private fun PocketScreenInternal(
    screenState: PocketScreenState,
    cards: ImmutableList<PocketCardUiModel>,
    onCardSelected: (PocketCardUiModel) -> Unit,
    onCardDismissed: () -> Unit,
    onShareId: () -> Unit,
    onSketchbookSelected: () -> Unit,
    onSketchbookDismissed: () -> Unit,
    onOpenCollectibles: () -> Unit
) {
    val listState = rememberLazyListState()
    val transition = updateTransition(screenState, label = "pocket_card_selection")
    val cardTilt = rememberCardTilt()

    PolkadotSurface {
        SharedTransitionLayout {
            CompositionLocalProvider(
                LocalSharedTransitionScope provides this,
                LocalCardTilt provides cardTilt
            ) {
                transition.AnimatedContent(
                    transitionSpec = { pocketFadeIn() togetherWith pocketFadeOut() },
                    contentKey = { it.contentKey }
                ) { current ->
                    CompositionLocalProvider(LocalNavAnimatedVisibilityScope provides this) {
                        when (current) {
                            is PocketScreenState.List -> {
                                PocketList(
                                    cards = cards,
                                    anchorCard = transition.extractAnchorCard(),
                                    listState = listState,
                                    collectiblesAvailable = current.collectiblesAvailable,
                                    onCardSelected = onCardSelected,
                                    onCollectiblesSelected = onSketchbookSelected
                                )
                            }

                            is PocketScreenState.CardDetails -> {
                                SelectedCardDetails(
                                    selectedCard = current.selectedCard,
                                    allCards = cards,
                                    onBack = onCardDismissed,
                                    onShareId = onShareId,
                                )
                            }

                            is PocketScreenState.Collectibles -> {
                                PocketCollectibles(
                                    onBack = onSketchbookDismissed,
                                    onViewButtonClick = onOpenCollectibles
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SelectedCardDetails(
    selectedCard: PocketCardUiModel,
    allCards: ImmutableList<PocketCardUiModel>,
    onBack: () -> Unit,
    onShareId: () -> Unit,
) {
    val cardIndex = allCards.indexOfFirst { it.id == selectedCard.id }
    when (selectedCard) {
        is PocketCardUiModel.DigitalDollar -> DigitalDollarCardDetails(
            card = selectedCard,
            onBack = onBack,
            cardIndex = cardIndex
        )

        is PocketCardUiModel.IdCard -> IdCardDetails(
            card = selectedCard,
            onBack = onBack,
            onShareClick = onShareId,
            cardIndex = cardIndex,
        )
    }
}

@Composable
private fun PocketList(
    cards: ImmutableList<PocketCardUiModel>,
    anchorCard: PocketCardUiModel?,
    listState: LazyListState,
    collectiblesAvailable: Boolean,
    onCardSelected: (PocketCardUiModel) -> Unit,
    onCollectiblesSelected: () -> Unit
) {
    val anchorIndex = cards.indexOfFirst { it.id == anchorCard?.id }

    val navigationBarInsets = LocalAppNavigationBarInsets.current

    Box {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
        ) {
            PolkadotTopBar(
                title = stringResource(RCommon.string.pocket_toolbar_title),
                titleSize = TopBarTitleSize.Large
            )

            LazyColumn(
                state = listState,
                verticalArrangement = Arrangement.spacedBy(-CardSizes.OVERLAP),
                contentPadding = WindowInsets(
                    top = PolkadotTheme.spacings.mediumIncreased,
                    bottom = PolkadotTheme.spacings.mediumIncreased,
                    left = PolkadotTheme.spacings.mediumIncreased,
                    right = PolkadotTheme.spacings.mediumIncreased
                ).add(navigationBarInsets).asPaddingValues()
            ) {
                itemsIndexed(cards) { index, card ->
                    val cardModifier = Modifier.pocketListCardSharedElement(
                        card = card,
                        index = index,
                        anchorCard = anchorCard,
                        anchorIndex = anchorIndex
                    )

                    when (card) {
                        is PocketCardUiModel.DigitalDollar -> {
                            DigitalDollarCard(
                                modifier = cardModifier,
                                card = card,
                                onSelected = onCardSelected,
                                isExpanded = false
                            )
                        }

                        is PocketCardUiModel.IdCard -> {
                            IdCard(
                                modifier = cardModifier,
                                card = card,
                                onSelected = onCardSelected,
                            )
                        }
                    }
                }
            }
        }

        AnimatedVisibility(
            modifier = Modifier
                .padding(horizontal = PolkadotTheme.spacings.mediumIncreased)
                .align(Alignment.BottomCenter)
                .layout { measurable, constraints ->
                    val placeable = measurable.measure(constraints)
                    val peek = navigationBarInsets.getBottom(this) + CollectiblesSketchbookPeek.roundToPx()
                    layout(placeable.width, peek) {
                        placeable.place(0, 0)
                    }
                }
                .pocketCollectiblesImageSharedElement(),
            visible = collectiblesAvailable,
            enter = fadeIn(),
            exit = fadeOut()
        ) {
            CollectiblesSketchbook(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(onClick = onCollectiblesSelected),
                blackAndWhite = true,
                onViewButtonClick = {}
            )
        }
    }
}

private fun Transition<PocketScreenState>.extractAnchorCard(): PocketCardUiModel? =
    (targetState as? PocketScreenState.CardDetails)?.selectedCard
        ?: (currentState as? PocketScreenState.CardDetails)?.selectedCard

@Preview
@Composable
private fun PocketScreenPreview() {
    PolkadotTheme {
        CompositionLocalProvider(
            LocalTokenAmountFormatter provides TokenAmountFormatter.mocked
        ) {
            PocketScreenInternal(
                screenState = PocketScreenState.List(collectiblesAvailable = true),
                cards = persistentListOf(
                    PocketCardUiModel.DigitalDollar(
                        amounts = LoadingState.Loaded(
                            PocketCardUiModel.DigitalDollar.Amounts(TokenAmountModel.mock, TokenAmountModel.mock)
                        ),
                        syncInProgress = false
                    ),
                    PocketCardUiModel.IdCard("username.99", "15oF4u...zaC1Ap", PocketRank.Basic)
                ),
                onCardSelected = {},
                onCardDismissed = {},
                onShareId = {},
                onSketchbookSelected = {},
                onSketchbookDismissed = {},
                onOpenCollectibles = {}
            )
        }
    }
}
