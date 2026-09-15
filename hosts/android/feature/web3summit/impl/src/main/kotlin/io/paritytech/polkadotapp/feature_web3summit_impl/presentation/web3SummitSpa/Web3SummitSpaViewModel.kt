package io.paritytech.polkadotapp.feature_web3summit_impl.presentation.web3SummitSpa

import android.webkit.WebView
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.common.utils.flowOf
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.feature_products_api.presentation.spaHost.SpaHost
import io.paritytech.polkadotapp.feature_products_api.presentation.spaHost.SpaHostSession
import io.paritytech.polkadotapp.feature_web3summit_api.presentation.PostOnboardingFlow
import io.paritytech.polkadotapp.feature_web3summit_impl.data.config.Web3SummitConfigProvider
import io.paritytech.polkadotapp.feature_web3summit_impl.domain.gate.Web3SummitGateState
import io.paritytech.polkadotapp.feature_web3summit_impl.domain.waitForUsernameOnChain.WaitForUsernameOnChainInteractor
import io.paritytech.polkadotapp.feature_web3summit_impl.domain.web3SummitSpa.Web3SummitSpaInteractor
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class Web3SummitSpaViewModel @Inject constructor(
    private val spaHost: SpaHost,
    gateState: Web3SummitGateState,
    private val configProvider: Web3SummitConfigProvider,
    private val postOnboardingFlow: PostOnboardingFlow,
    private val interactor: Web3SummitSpaInteractor,
    private val waitForUsernameInteractor: WaitForUsernameOnChainInteractor,
) : BaseViewModel() {
    // Created once the config resolves from remote config; null until then.
    private val sessionState = MutableStateFlow<SpaHostSession?>(null)

    private val usernameEstablished = MutableStateFlow(false)

    private val attendanceConfirmed = MutableStateFlow(false)

    @OptIn(ExperimentalCoroutinesApi::class)
    val webView: StateFlow<WebView?> = sessionState
        .flatMapLatest { session -> session?.webView ?: emptyFlow() }
        .stateIn(viewModelScope, SharingStarted.Eagerly, null)

    val state: StateFlow<Web3SummitSpaUiState> = combine(
        flowOf { gateState.isSkippable() },
        usernameEstablished,
        attendanceConfirmed,
    ) { isSkippable, usernameEstablished, confirmed ->
        Web3SummitSpaUiState(
            showSkipButton = isSkippable && !confirmed,
            isAttendanceConfirmed = confirmed,
            showUsernameEstablishing = !usernameEstablished
        )
    }.stateIn(viewModelScope, SharingStarted.Eagerly, Web3SummitSpaUiState())

    init {
        createSession()
        awaitUsernameEstablished()
        awaitAttendanceConfirmation()
    }

    private fun createSession() {
        launch {
            configProvider.getConfig()
                .logFailure("Failed to load web3summit config")
                .onSuccess { config -> sessionState.value = spaHost.createSession(config.dotNsUrl) }
        }
    }

    fun onSkipClick() {
        interactor.markVerifiedManually()
        launch { postOnboardingFlow.openPostOnboarding() }
    }

    fun onStartUsingAppClick() {
        launch { postOnboardingFlow.openPostOnboarding() }
    }

    fun pauseConnections() {
        sessionState.value?.pauseConnections()
    }

    fun resumeConnections() {
        sessionState.value?.resumeConnections()
    }

    private fun awaitUsernameEstablished() {
        launch {
            waitForUsernameInteractor.awaitLightPersonhoodEstablished()
                .logFailure("Username establishing failed")
                .onSuccess { usernameEstablished.value = true }
        }
    }

    private fun awaitAttendanceConfirmation() {
        launch {
            interactor.awaitAttendanceConfirmed()
                .logFailure("W3S attendance polling failed terminally")
                .onSuccess { attendanceConfirmed.value = true }
        }
    }
}
