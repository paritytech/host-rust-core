package io.paritytech.polkadotapp.feature_chats_impl.presentation.search

import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.common.presentation.search.SearchState
import io.paritytech.polkadotapp.common.presentation.search.withQuerySearching
import io.paritytech.polkadotapp.common.utils.SizedList
import io.paritytech.polkadotapp.common.utils.mapList
import io.paritytech.polkadotapp.common.utils.shareInBackground
import io.paritytech.polkadotapp.feature_chats_api.domain.error.asStartChatError
import io.paritytech.polkadotapp.feature_chats_api.presentation.error.toPresentationError
import io.paritytech.polkadotapp.feature_chats_impl.ChatsRouter
import io.paritytech.polkadotapp.feature_chats_impl.domain.interactors.AddContactInteractor
import io.paritytech.polkadotapp.feature_chats_impl.domain.models.ChatAvatar
import io.paritytech.polkadotapp.feature_chats_impl.domain.models.ContactSearchResult
import io.paritytech.polkadotapp.feature_chats_impl.domain.models.StartChatData
import io.paritytech.polkadotapp.feature_chats_impl.presentation.feed.models.toUi
import io.paritytech.polkadotapp.feature_chats_impl.presentation.search.models.UserSearchResultUiModel
import io.paritytech.polkadotapp.feature_chats_impl.presentation.search.models.toChatFeedPayload
import io.paritytech.polkadotapp.feature_usernames_api.presentation.filterAvailableUsernameSymbols
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
internal class AddContactViewModel @Inject constructor(
    private val interactor: AddContactInteractor,
    private val router: ChatsRouter,
) : BaseViewModel(), AddContactContract {
    private val searchQuery = MutableStateFlow("")

    private val searchResult: Flow<SearchState<SizedList<UserSearchResultUiModel>>> = searchQuery
        .withQuerySearching { query ->
            interactor.searchContacts(query)
                .mapList { it.toUi() }
        }
        .shareInBackground()

    private val loadingContactId = MutableStateFlow<AccountId?>(null)

    override val state: StateFlow<AddContactUiState> = combine(
        searchQuery,
        searchResult,
        loadingContactId
    ) { query, result, loadingId ->
        AddContactUiState(
            searchQuery = query,
            searchResult = result,
            loadingContactId = loadingId
        )
    }.stateIn(
        scope = this,
        started = SharingStarted.Eagerly,
        initialValue = AddContactUiState()
    )

    override fun onSearchChange(value: String) {
        searchQuery.update { value.filterAvailableUsernameSymbols() }
    }

    override fun onSearchResultClick(result: UserSearchResultUiModel) {
        if (loadingContactId.value != null) return

        launch {
            loadingContactId.value = result.contactAccountId

            interactor.getStartChatData(result.contactAccountId)
                .onSuccess(::openChatFeed)
                .onFailure { showPresentationError(it.asStartChatError().toPresentationError()) }

            loadingContactId.value = null
        }
    }

    override fun onCancelClick() {
        router.back()
    }

    override fun onScanClick() {
        router.openScan()
    }

    private fun ContactSearchResult.toUi(): UserSearchResultUiModel {
        val displayUsername = username.getDisplayUsername()
        return UserSearchResultUiModel(
            contactAccountId = accountId,
            username = displayUsername,
            avatarModel = ChatAvatar.Account(displayUsername, accountId.value).toUi(),
        )
    }

    private fun openChatFeed(startChatData: StartChatData) {
        router.openChatFeed(startChatData.toChatFeedPayload())
    }
}
