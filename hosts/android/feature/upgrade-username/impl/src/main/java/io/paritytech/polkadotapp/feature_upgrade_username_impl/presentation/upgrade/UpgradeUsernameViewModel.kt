package io.paritytech.polkadotapp.feature_upgrade_username_impl.presentation.upgrade

import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.R
import io.paritytech.polkadotapp.common.presentation.resources.ContextManager
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.feature_upgrade_username_api.domain.model.UpgradeUsernameAvailabilityState
import io.paritytech.polkadotapp.feature_upgrade_username_impl.domain.interactor.UsernameUpgradeInteractor
import io.paritytech.polkadotapp.feature_upgrade_username_impl.presentation.UpgradeUsernameRouter
import io.paritytech.polkadotapp.feature_usernames_api.presentation.MIN_USERNAME_LENGTH
import io.paritytech.polkadotapp.feature_usernames_api.presentation.filterUsernameInput
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.mapLatest
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject
import kotlin.time.Duration.Companion.milliseconds

@HiltViewModel
class UpgradeUsernameViewModel @Inject constructor(
    private val router: UpgradeUsernameRouter,
    private val contextManager: ContextManager,
    private val interactor: UsernameUpgradeInteractor
) : BaseViewModel(), UpgradeUsernameContract {
    private val username = MutableStateFlow("")
    private val fieldState = MutableStateFlow(UpgradeUsernameFieldState.Neutral)
    private val isClaimingInProgress = MutableStateFlow(false)

    override val uiState: StateFlow<UpgradeUsernameUiState> = combine(
        username,
        fieldState,
        isClaimingInProgress
    ) { username, fieldState, isClaimingInProgress ->
        UpgradeUsernameUiState(username, fieldState, isClaimingInProgress)
    }
        .stateIn(this, SharingStarted.Eagerly, UpgradeUsernameUiState())

    init {
        observeUsernameChanges()
        prefillInputWithLiteUsername()
    }

    override fun onUsernameChanged(value: String) {
        val previousValue = uiState.value.username
        val newValue = value.filterUsernameInput()

        if (previousValue != newValue) {
            username.value = newValue
            fieldState.value = UpgradeUsernameFieldState.Neutral
        }
    }

    override fun onClaimAction() {
        isClaimingInProgress.value = true

        launch {
            interactor.upgrade(username = uiState.value.username)
                .onSuccess {
                    onBackClick()
                }
                .onFailure {
                    showError(it)
                    isClaimingInProgress.value = false
                }
        }
    }

    private fun prefillInputWithLiteUsername() = launch {
        onUsernameChanged(interactor.liteUsername().base)
    }

    private fun observeUsernameChanges() {
        uiState.map { it.username }
            .distinctUntilChanged()
            .debounce(300.milliseconds)
            .filter { it.length >= MIN_USERNAME_LENGTH }
            .mapLatest { username ->
                fieldState.value = UpgradeUsernameFieldState.Neutral
                interactor.checkUsernameAvailable(username)
                    .onSuccess { availabilityState ->
                        val newFieldState = when (availabilityState) {
                            is UpgradeUsernameAvailabilityState.NotAvailable -> UpgradeUsernameFieldState.Taken
                            else -> UpgradeUsernameFieldState.Available
                        }

                        fieldState.value = newFieldState
                    }
                    .onFailure {
                        showError(contextManager.applicationContext.getString(R.string.chat_failed_to_become_peer))
                        fieldState.value = UpgradeUsernameFieldState.Invalid
                        Timber.d(it)
                    }
            }
            .launchIn(this)
    }

    override fun onBackClick() {
        router.back()
    }
}
