package io.paritytech.polkadotapp.feature_chats_impl.presentation.search

import androidx.compose.runtime.Immutable
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.presentation.search.SearchState
import io.paritytech.polkadotapp.common.utils.SizedList
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatId
import io.paritytech.polkadotapp.feature_chats_impl.presentation.chatSearch.models.RecentChatUiModel
import io.paritytech.polkadotapp.feature_chats_impl.presentation.search.models.UserSearchResultUiModel
import kotlinx.collections.immutable.ImmutableList
import kotlinx.coroutines.flow.StateFlow

@Immutable
data class AddContactUiState(
    val searchQuery: String,
    val searchResult: SearchState<SizedList<UserSearchResultUiModel>>,
    val loadingContactId: AccountId?,
    val recents: ImmutableList<RecentChatUiModel>,
)

interface AddContactContract {
    val state: StateFlow<AddContactUiState>

    fun onSearchChange(value: String)
    fun onSearchResultClick(result: UserSearchResultUiModel)
    fun onRecentClick(chatId: ChatId)
}
