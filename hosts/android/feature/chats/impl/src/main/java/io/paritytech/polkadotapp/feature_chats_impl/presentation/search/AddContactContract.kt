package io.paritytech.polkadotapp.feature_chats_impl.presentation.search

import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.presentation.search.SearchState
import io.paritytech.polkadotapp.common.utils.SizedList
import io.paritytech.polkadotapp.feature_chats_impl.presentation.search.models.UserSearchResultUiModel
import kotlinx.coroutines.flow.StateFlow

data class AddContactUiState(
    val searchQuery: String = "",
    val searchResult: SearchState<SizedList<UserSearchResultUiModel>> = SearchState.Initial,
    val loadingContactId: AccountId? = null
)

interface AddContactContract {
    val state: StateFlow<AddContactUiState>

    fun onSearchChange(value: String)
    fun onSearchResultClick(result: UserSearchResultUiModel)
    fun onCancelClick()
    fun onScanClick()
}
