package io.paritytech.polkadotapp.feature_chats_impl.presentation.search.compose

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import androidx.compose.ui.util.lerp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.paritytech.polkadotapp.common.domain.model.intoAccountId
import io.paritytech.polkadotapp.common.presentation.notification.rememberAppNotifier
import io.paritytech.polkadotapp.common.presentation.screens.ObserveViewModelEvents
import io.paritytech.polkadotapp.common.presentation.search.SearchState
import io.paritytech.polkadotapp.common.utils.SizedList
import io.paritytech.polkadotapp.common.utils.randomBytes
import io.paritytech.polkadotapp.common.utils.toSizedList
import io.paritytech.polkadotapp.design.components.avatar.AvatarUiModel
import io.paritytech.polkadotapp.design.components.avatar.Mock
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.topbar.PolkadotSearchField
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatId
import io.paritytech.polkadotapp.feature_chats_impl.presentation.chatSearch.models.NoRowStatus
import io.paritytech.polkadotapp.feature_chats_impl.presentation.chatSearch.models.RecentChatUiModel
import io.paritytech.polkadotapp.feature_chats_impl.presentation.search.AddContactUiState
import io.paritytech.polkadotapp.feature_chats_impl.presentation.search.AddContactViewModel
import io.paritytech.polkadotapp.feature_chats_impl.presentation.search.compose.components.AddContactSearchContent
import io.paritytech.polkadotapp.feature_chats_impl.presentation.search.models.UserSearchResultUiModel
import io.paritytech.polkadotapp.feature_chats_impl.presentation.util.rememberCompositionViewModelStoreOwner
import kotlinx.collections.immutable.persistentListOf
import kotlinx.collections.immutable.toImmutableList
import kotlin.random.Random
import io.paritytech.polkadotapp.common.R as RCommon

private val ScannerCornerRadius = 32.dp
private val ScannerThumbnailSize = 64.dp
private val ScannerThumbnailCornerRadius = 16.dp

@Composable
fun AddContactPanel(
    modifier: Modifier = Modifier,
    scanner: @Composable (Modifier) -> Unit,
) {
    val viewModel = hiltViewModel<AddContactViewModel>(viewModelStoreOwner = rememberCompositionViewModelStoreOwner())
    val state by viewModel.state.collectAsStateWithLifecycle()
    var searchActive by remember { mutableStateOf(false) }
    val focusManager = LocalFocusManager.current

    ObserveViewModelEvents(viewModel, rememberAppNotifier())

    val actions = remember(viewModel, focusManager) {
        AddContactPanelActions(
            onSearchFocused = { searchActive = true },
            onSearchChange = viewModel::onSearchChange,
            onCloseSearch = {
                focusManager.clearFocus()
                viewModel.onSearchChange("")
                searchActive = false
            },
            onSearchResultClick = viewModel::onSearchResultClick,
            onRecentClick = viewModel::onRecentClick,
        )
    }

    BackHandler(enabled = searchActive, onBack = actions.onCloseSearch)

    AddContactPanelInternal(
        modifier = modifier,
        state = state,
        searchActive = searchActive,
        actions = actions,
        scanner = scanner,
    )
}

@Composable
private fun AddContactPanelInternal(
    modifier: Modifier,
    state: AddContactUiState,
    searchActive: Boolean,
    actions: AddContactPanelActions,
    scanner: @Composable (Modifier) -> Unit,
) {
    Column(modifier = modifier) {
        ScannerSearchArea(
            modifier = Modifier
                .weight(1f, fill = false)
                .squareUpToMaxHeight(),
            state = state,
            searchActive = searchActive,
            actions = actions,
            scanner = scanner,
        )

        VerticalSpacer { small }

        PolkadotSearchField(
            modifier = Modifier
                .fillMaxWidth()
                .onFocusChanged { if (it.hasFocus) actions.onSearchFocused() },
            value = state.searchQuery,
            onValueChange = actions.onSearchChange,
            onClear = {
                if (state.searchQuery.isEmpty()) actions.onCloseSearch() else actions.onSearchChange("")
            },
            placeholder = stringResource(RCommon.string.add_contact_search_placeholder),
            showClear = searchActive,
        )
    }
}

@Composable
private fun ScannerSearchArea(
    modifier: Modifier,
    state: AddContactUiState,
    searchActive: Boolean,
    actions: AddContactPanelActions,
    scanner: @Composable (Modifier) -> Unit,
) {
    val shrinkProgress = animateFloatAsState(
        targetValue = if (searchActive) 1f else 0f,
        label = "ScannerShrinkProgress"
    )

    Box(modifier = modifier) {
        AnimatedVisibility(
            visible = searchActive,
            enter = fadeIn(),
            exit = fadeOut(),
        ) {
            AddContactSearchContent(
                state = state,
                bottomInset = ScannerThumbnailSize,
                onSearchResultClick = actions.onSearchResultClick,
                onRecentClick = actions.onRecentClick,
            )
        }

        ShrinkingScanner(shrinkProgress = shrinkProgress, scanner = scanner)

        if (searchActive) {
            ScannerThumbnailClickArea(onClick = actions.onCloseSearch)
        }
    }
}

// Scaled rather than resized, so the camera surface is not re-laid out on every animation frame.
@Composable
private fun BoxScope.ShrinkingScanner(
    shrinkProgress: State<Float>,
    scanner: @Composable (Modifier) -> Unit,
) {
    PolkadotSurface(
        // Sized by the height: above the keyboard the area can be shorter than wide, and a width-sized square
        // would overflow it and get centered, dropping the thumbnail below the area's bottom edge.
        modifier = Modifier
            .align(Alignment.BottomCenter)
            .fillMaxHeight()
            .aspectRatio(1f, matchHeightConstraintsFirst = true)
            .graphicsLayer {
                val progress = shrinkProgress.value
                val thumbnailScale = if (size.width > 0f) ScannerThumbnailSize.toPx() / size.width else 1f
                val scale = lerp(1f, thumbnailScale, progress)
                val cornerRadius = lerp(ScannerCornerRadius.toPx(), ScannerThumbnailCornerRadius.toPx(), progress)

                scaleX = scale
                scaleY = scale
                transformOrigin = TransformOrigin(0.5f, 1f)
                // The clip is scaled together with the content, so it is set in pre-scale pixels.
                shape = RoundedCornerShape(cornerRadius / scale)
                clip = true
            },
        color = PolkadotTheme.colors.bg.surface.nested,
    ) {
        scanner(Modifier.fillMaxSize())
    }
}

// Sits above the scanner so a tap on the thumbnail always closes search, even where the scanner's own content
// (e.g. the camera permission hint) would take it.
@Composable
private fun BoxScope.ScannerThumbnailClickArea(onClick: () -> Unit) {
    PolkadotSurface(
        modifier = Modifier
            .align(Alignment.BottomCenter)
            .size(ScannerThumbnailSize),
        shape = RoundedCornerShape(ScannerThumbnailCornerRadius),
        color = Color.Transparent,
        onClick = onClick,
    ) {}
}

// A width-sized square that gives up height when the column has less room, e.g. above the keyboard on short screens.
private fun Modifier.squareUpToMaxHeight(): Modifier = layout { measurable, constraints ->
    val width = constraints.maxWidth
    val height = width.coerceAtMost(constraints.maxHeight)
    val placeable = measurable.measure(Constraints.fixed(width, height))

    layout(width, height) {
        placeable.place(0, 0)
    }
}

@Immutable
private data class AddContactPanelActions(
    val onSearchFocused: () -> Unit,
    val onSearchChange: (String) -> Unit,
    val onCloseSearch: () -> Unit,
    val onSearchResultClick: (UserSearchResultUiModel) -> Unit,
    val onRecentClick: (ChatId) -> Unit,
)

@Composable
private fun AddContactPanelPreview(state: AddContactUiState, searchActive: Boolean) {
    PolkadotTheme {
        PolkadotSurface(color = PolkadotTheme.colors.bg.surface.container) {
            AddContactPanelInternal(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(PolkadotTheme.spacings.small),
                state = state,
                searchActive = searchActive,
                actions = AddContactPanelActions(
                    onSearchFocused = {},
                    onSearchChange = {},
                    onCloseSearch = {},
                    onSearchResultClick = {},
                    onRecentClick = {},
                ),
                scanner = { modifier -> Box(modifier = modifier) },
            )
        }
    }
}

@Preview(widthDp = 380)
@Composable
private fun AddContactPanelScannerPreview() {
    AddContactPanelPreview(
        state = previewState(query = "", searchResult = SearchState.Initial),
        searchActive = false,
    )
}

@Preview(widthDp = 380)
@Composable
private fun AddContactPanelNoRecentsPreview() {
    AddContactPanelPreview(
        state = previewState(query = "", searchResult = SearchState.Initial),
        searchActive = true,
    )
}

@Preview(widthDp = 380)
@Composable
private fun AddContactPanelRecentsPreview() {
    val recents = listOf("mosticRiver.88", "delaware.01", "franz", "dmitry.01", "euclid.01").map { name ->
        val accountId = Random.randomBytes(32).intoAccountId()
        RecentChatUiModel(
            chatId = ChatId.fromContact(accountId),
            key = name,
            title = name,
            avatarModel = AvatarUiModel.Mock.fromName(name),
            status = NoRowStatus,
            isMenuOpen = false,
        )
    }

    AddContactPanelPreview(
        state = previewState(query = "", searchResult = SearchState.Initial).copy(recents = recents.toImmutableList()),
        searchActive = true,
    )
}

@Preview(widthDp = 380)
@Composable
private fun AddContactPanelResultsPreview() {
    val users = listOf("mosticRiver.88", "monster.01", "molecule", "mostwanted", "morales").map { name ->
        UserSearchResultUiModel(
            contactAccountId = Random.randomBytes(32).intoAccountId(),
            username = name,
            avatarModel = AvatarUiModel.Mock.fromName(name),
        )
    }

    AddContactPanelPreview(
        state = previewState(query = "Mo", searchResult = SearchState.Loaded(users.toSizedList())),
        searchActive = true,
    )
}

private fun previewState(
    query: String,
    searchResult: SearchState<SizedList<UserSearchResultUiModel>>,
) = AddContactUiState(
    searchQuery = query,
    searchResult = searchResult,
    loadingContactId = null,
    recents = persistentListOf(),
)
