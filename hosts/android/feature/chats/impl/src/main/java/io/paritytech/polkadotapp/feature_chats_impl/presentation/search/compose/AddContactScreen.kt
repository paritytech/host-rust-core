package io.paritytech.polkadotapp.feature_chats_impl.presentation.search.compose

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.HorizontalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.domain.model.intoAccountId
import io.paritytech.polkadotapp.common.presentation.search.SearchState
import io.paritytech.polkadotapp.common.utils.SizedList
import io.paritytech.polkadotapp.common.utils.randomBytes
import io.paritytech.polkadotapp.common.utils.toSizedList
import io.paritytech.polkadotapp.design.components.avatar.AvatarUiModel
import io.paritytech.polkadotapp.design.components.avatar.Mock
import io.paritytech.polkadotapp.design.components.avatar.NovaContactItem
import io.paritytech.polkadotapp.design.components.avatar.NovaContactItemType
import io.paritytech.polkadotapp.design.components.progress.NovaCircularProgressIndicator
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.design.utils.withBold
import io.paritytech.polkadotapp.feature_chats_impl.presentation.search.AddContactContract
import io.paritytech.polkadotapp.feature_chats_impl.presentation.search.compose.components.SearchHeader
import io.paritytech.polkadotapp.feature_chats_impl.presentation.search.models.UserSearchResultUiModel
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.persistentListOf
import kotlin.random.Random
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun AddContactScreen(contract: AddContactContract) {
    val state by contract.state.collectAsStateWithLifecycle()

    AddContactScreenInternal(
        searchQuery = state.searchQuery,
        searchResult = state.searchResult,
        loadingContactId = state.loadingContactId,
        onSearchChange = contract::onSearchChange,
        onSearchResultClick = contract::onSearchResultClick,
        onCancelClick = contract::onCancelClick,
        onScanClick = contract::onScanClick
    )
}

@Composable
private fun AddContactScreenInternal(
    searchQuery: String,
    searchResult: SearchState<SizedList<UserSearchResultUiModel>>,
    loadingContactId: AccountId?,
    onSearchChange: (String) -> Unit,
    onSearchResultClick: (UserSearchResultUiModel) -> Unit,
    onCancelClick: () -> Unit,
    onScanClick: () -> Unit,
) {
    PolkadotSurface {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .safeDrawingPadding()
        ) {
            VerticalSpacer { small }

            SearchHeader(
                searchQuery = searchQuery,
                onSearchChange = onSearchChange,
                onCancelClick = onCancelClick,
                onScanClick = onScanClick
            )

            VerticalSpacer { extraMedium }

            when (searchResult) {
                SearchState.Initial -> InitialState()
                SearchState.Loading -> LoadingState()
                SearchState.Empty -> EmptyState(searchQuery)
                is SearchState.Error -> ErrorState()
                is SearchState.Loaded -> LoadedState(
                    results = searchResult.results,
                    loadingContactId = loadingContactId,
                    onSearchResultClick = onSearchResultClick,
                )
            }
        }
    }
}

@Composable
private fun InitialState() {
    CenteredMessage(text = stringResource(RCommon.string.chats_empty_state_message))
}

@Composable
private fun EmptyState(query: String) {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        NovaText(
            modifier = Modifier
                .fillMaxWidth()
                .padding(
                    horizontal = PolkadotTheme.spacings.large,
                    vertical = PolkadotTheme.spacings.extraMedium
                ),
            text = stringResource(RCommon.string.common_no_results_for, query).withBold(query),
            style = PolkadotTheme.typography.title.medium,
            color = PolkadotTheme.colors.fg.secondary,
            textAlign = TextAlign.Center
        )
    }
}

@Composable
private fun ErrorState() {
    CenteredMessage(text = stringResource(RCommon.string.add_contact_search_error))
}

@Composable
private fun LoadingState() {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        NovaCircularProgressIndicator(
            modifier = Modifier.size(32.dp),
            color = PolkadotTheme.colors.fg.primary,
            strokeWidth = 3.dp
        )
    }
}

@Composable
private fun CenteredMessage(text: String) {
    NovaText(
        modifier = Modifier
            .fillMaxWidth()
            .padding(
                horizontal = PolkadotTheme.spacings.large,
                vertical = PolkadotTheme.spacings.extraMedium
            ),
        text = text,
        style = PolkadotTheme.typography.body.large,
        color = PolkadotTheme.colors.fg.primary,
        textAlign = TextAlign.Center
    )
}

@Composable
private fun LoadedState(
    results: ImmutableList<UserSearchResultUiModel>,
    loadingContactId: AccountId?,
    onSearchResultClick: (UserSearchResultUiModel) -> Unit,
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize()
    ) {
        itemsIndexed(
            items = results,
            key = { _, contact -> contact.contactAccountId.value.toHexString() },
        ) { index, contact ->
            val isLoading = contact.contactAccountId == loadingContactId
            val onClick = remember(contact) { { onSearchResultClick(contact) } }

            NovaContactItem(
                title = contact.username,
                type = NovaContactItemType.User,
                avatarModel = contact.avatarModel,
                onClick = onClick,
                endContent = if (isLoading) {
                    {
                        NovaCircularProgressIndicator(
                            modifier = Modifier.size(20.dp),
                            color = PolkadotTheme.colors.fg.primary,
                            strokeWidth = 2.dp
                        )
                    }
                } else null
            )

            if (index != results.lastIndex) {
                HorizontalDivider(modifier = Modifier.padding(start = 80.dp))
            }
        }
    }
}

@Preview
@Composable
private fun AddContactScreenInitialPreview() {
    PolkadotTheme {
        AddContactScreenInternal(
            searchQuery = "",
            searchResult = SearchState.Initial,
            loadingContactId = null,
            onSearchChange = {},
            onSearchResultClick = {},
            onCancelClick = {},
            onScanClick = {}
        )
    }
}

@Preview
@Composable
private fun AddContactScreenLoadingPreview() {
    PolkadotTheme {
        AddContactScreenInternal(
            searchQuery = "jul",
            searchResult = SearchState.Loading,
            loadingContactId = null,
            onSearchChange = {},
            onSearchResultClick = {},
            onCancelClick = {},
            onScanClick = {}
        )
    }
}

@Preview
@Composable
private fun AddContactScreenEmptyPreview() {
    PolkadotTheme {
        AddContactScreenInternal(
            searchQuery = "zzzz",
            searchResult = SearchState.Empty,
            loadingContactId = null,
            onSearchChange = {},
            onSearchResultClick = {},
            onCancelClick = {},
            onScanClick = {}
        )
    }
}

@Preview
@Composable
private fun AddContactScreenErrorPreview() {
    PolkadotTheme {
        AddContactScreenInternal(
            searchQuery = "jul",
            searchResult = SearchState.Error(RuntimeException("network error")),
            loadingContactId = null,
            onSearchChange = {},
            onSearchResultClick = {},
            onCancelClick = {},
            onScanClick = {}
        )
    }
}

@Preview
@Composable
private fun AddContactScreenWithResultsPreview() {
    val loadingAccountId = Random.randomBytes(32).intoAccountId()
    PolkadotTheme {
        AddContactScreenInternal(
            searchQuery = "jul",
            searchResult = SearchState.Loaded(
                persistentListOf(
                    UserSearchResultUiModel(
                        contactAccountId = Random.randomBytes(32).intoAccountId(),
                        username = "Julius.87",
                        avatarModel = AvatarUiModel.Mock.fromName("Julius.87")
                    ),
                    UserSearchResultUiModel(
                        contactAccountId = loadingAccountId,
                        username = "Julian.56",
                        avatarModel = AvatarUiModel.Mock.fromName("Julian.56")
                    ),
                    UserSearchResultUiModel(
                        contactAccountId = Random.randomBytes(32).intoAccountId(),
                        username = "Juliette.73",
                        avatarModel = AvatarUiModel.Mock.fromName("Juliette.73")
                    )
                ).toSizedList()
            ),
            loadingContactId = loadingAccountId,
            onSearchChange = {},
            onSearchResultClick = {},
            onCancelClick = {},
            onScanClick = {}
        )
    }
}
