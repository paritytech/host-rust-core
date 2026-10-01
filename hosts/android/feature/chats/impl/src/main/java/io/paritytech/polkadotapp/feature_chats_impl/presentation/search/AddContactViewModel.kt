package io.paritytech.polkadotapp.feature_chats_impl.presentation.search

import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.common.presentation.search.SearchState
import io.paritytech.polkadotapp.common.presentation.search.withQuerySearching
import io.paritytech.polkadotapp.common.utils.SizedList
import io.paritytech.polkadotapp.common.utils.inBackground
import io.paritytech.polkadotapp.common.utils.launchUnit
import io.paritytech.polkadotapp.common.utils.mapList
import io.paritytech.polkadotapp.common.utils.shareInBackground
import io.paritytech.polkadotapp.feature_chats_api.domain.error.asStartChatError
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatId
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatVariant
import io.paritytech.polkadotapp.feature_chats_api.presentation.error.toPresentationError
import io.paritytech.polkadotapp.feature_chats_api.presentation.model.ChatFeedPayload
import io.paritytech.polkadotapp.feature_chats_impl.ChatsRouter
import io.paritytech.polkadotapp.feature_chats_impl.domain.interactors.AddContactInteractor
import io.paritytech.polkadotapp.feature_chats_impl.domain.models.ChatAvatar
import io.paritytech.polkadotapp.feature_chats_impl.domain.models.ContactSearchResult
import io.paritytech.polkadotapp.feature_chats_impl.domain.models.StartChatData
import io.paritytech.polkadotapp.feature_chats_impl.presentation.chatSearch.models.toRecentUi
import io.paritytech.polkadotapp.feature_chats_impl.presentation.feed.models.toUi
import io.paritytech.polkadotapp.feature_chats_impl.presentation.search.models.UserSearchResultUiModel
import io.paritytech.polkadotapp.feature_chats_impl.presentation.search.models.toChatFeedPayload
import io.paritytech.polkadotapp.feature_usernames_api.presentation.filterAvailableUsernameSymbols
import kotlinx.collections.immutable.persistentListOf
import kotlinx.collections.immutable.toImmutableList
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
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

    private val recents = interactor.observeRecentChats()
        .map { chats -> chats.map { it.toRecentUi(isMenuOpen = false) }.toImmutableList() }
        .inBackground()

    override val state: StateFlow<AddContactUiState> = combine(
        searchQuery,
        searchResult,
        loadingContactId,
        recents
    ) { query, result, loadingId, recentsUi ->
        AddContactUiState(
            searchQuery = query,
            searchResult = result,
            loadingContactId = loadingId,
            recents = recentsUi
        )
    }.stateIn(
        scope = this,
        started = SharingStarted.Eagerly,
        initialValue = InitialAddContactUiState
    )

    override fun onSearchChange(value: String) {
        searchQuery.update { value.filterAvailableUsernameSymbols() }
    }

    override fun onSearchResultClick(result: UserSearchResultUiModel) {
        if (loadingContactId.value != null) return

        launch {
            loadingContactId.value = result.contactAccountId

            interactor.getStartChatData(result.contactAccountId)
                .onSuccess { startChatData ->
                    interactor.addRecent(ChatId.fromContact(result.contactAccountId))
                    openChatFeed(startChatData)
                }
                .onFailure { showPresentationError(it.asStartChatError().toPresentationError()) }

            loadingContactId.value = null
        }
    }

    override fun onRecentClick(chatId: ChatId) = launchUnit {
        when (val variant = chatId.chatVariant()) {
            is ChatVariant.Contact -> {
                interactor.getStartChatData(variant.contactAccountId)
                    .onSuccess(::openChatFeed)
                    .onFailure { showPresentationError(it.asStartChatError().toPresentationError()) }
            }

            is ChatVariant.Extension -> {
                router.openChatFeed(ChatFeedPayload.existingChat(chatId))
            }
        }
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

private val InitialAddContactUiState = AddContactUiState(
    searchQuery = "",
    searchResult = SearchState.Initial,
    loadingContactId = null,
    recents = persistentListOf()
)
