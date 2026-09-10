package io.paritytech.polkadotapp.app.root.presentation.root

import android.net.Uri
import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.app.root.domain.RootInteractor
import io.paritytech.polkadotapp.app.root.presentation.main.BottomNavHeightProvider
import io.paritytech.polkadotapp.common.presentation.deeplink.DeepLinkHandler
import io.paritytech.polkadotapp.common.presentation.deeplink.DeeplinkProcessingOutcome
import io.paritytech.polkadotapp.common.presentation.deeplink.flatten
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.common.utils.FeatureOption
import io.paritytech.polkadotapp.common.utils.OneShotEventChannel
import io.paritytech.polkadotapp.common.utils.disable
import io.paritytech.polkadotapp.common.utils.enable
import io.paritytech.polkadotapp.common.utils.isEnabled
import io.paritytech.polkadotapp.common.utils.shareInBackground
import io.paritytech.polkadotapp.feature_chats_api.domain.chatRequest.ChatRequestServiceCoordinator
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatBotStateController
import io.paritytech.polkadotapp.feature_chats_impl.domain.ChatEngine
import io.paritytech.polkadotapp.feature_coinage_api.domain.externalPayment.ExternalPaymentWorkerStarter
import io.paritytech.polkadotapp.feature_coinage_api.domain.service.CoinageServiceStarter
import io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin.ChainHealthMixin
import io.paritytech.polkadotapp.feature_fund_api.domain.AutoConvertDepositService
import io.paritytech.polkadotapp.feature_products_impl.domain.exploreProducts.ExploreProductsService
import io.paritytech.polkadotapp.feature_settings_impl.domain.interactors.SyncPriceCurrencyChange
import io.paritytech.polkadotapp.feature_splash_api.presentation.SplashPassedObserver
import io.paritytech.polkadotapp.feature_sso_impl.domain.SsoService
import io.paritytech.polkadotapp.feature_statement_store_api.domain.slotAllocator.StatementStoreSlotAllocator
import io.paritytech.polkadotapp.feature_usernames_api.domain.usecase.ObserveAccountOnboardingStatusUseCase
import io.paritytech.polkadotapp.feature_web3summit_api.domain.ObserveWeb3SummitEndedUseCase
import io.paritytech.polkadotapp.feature_web3summit_api.presentation.PostOnboardingFlow
import io.paritytech.polkadotapp.feature_web3summit_impl.domain.warmUp.Web3SummitWarmUpService
import io.paritytech.polkadotapp.tools_jwt_auth_impl.domain.warmUp.JwtAuthWarmUpService
import io.paritytech.polkadotapp.tools_remoteconfig_api.RemoteConfigService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject

@HiltViewModel
class RootViewModel @Inject constructor(
    private val rootInteractor: RootInteractor,
    private val syncPriceCurrencyChange: SyncPriceCurrencyChange,
    private val deeplinkHandler: DeepLinkHandler,
    private val splashPassedObserver: SplashPassedObserver,
    private val remoteConfigService: RemoteConfigService,
    private val depositService: AutoConvertDepositService,
    private val coinageServiceStarter: CoinageServiceStarter,
    private val externalPaymentWorkerStarter: ExternalPaymentWorkerStarter,
    private val statementStoreSlotAllocator: StatementStoreSlotAllocator,
    private val ssoService: SsoService,
    private val chatRequestServiceCoordinator: ChatRequestServiceCoordinator,
    private val exploreProductsService: ExploreProductsService,
    private val web3SummitWarmUpService: Web3SummitWarmUpService,
    private val observeWeb3SummitEnded: ObserveWeb3SummitEndedUseCase,
    private val postOnboardingFlow: PostOnboardingFlow,
    private val jwtAuthWarmUpService: JwtAuthWarmUpService,
    chatBotStateController: ChatBotStateController,
    chatEngine: ChatEngine,
    observeAccountOnboardingStatus: ObserveAccountOnboardingStatusUseCase,
    bottomNavHeightProvider: BottomNavHeightProvider,
    chainHealthMixinFactory: ChainHealthMixin.Factory,
) : BaseViewModel(), RootContract {
    override val chatOverlays = chatEngine.observeActiveOverlays()
    override val isOnboarded = observeAccountOnboardingStatus().map { it.isOnboarded }
    override val bottomNavHeight = bottomNavHeightProvider.heightDp
    override val chainsHealth = chainHealthMixinFactory.create(this).model

    init {
        launch {
            remoteConfigService.sync()
                .onSuccess {
                    launch { rootInteractor.syncPrices() }
                    launch { depositService.startObserveAndConvert() }
                    launch { syncPriceCurrencyChange.startObserving() }
                    launch { coinageServiceStarter.start() }
                    externalPaymentWorkerStarter.start()
                    launch { statementStoreSlotAllocator.scheduleSlotRenewals() }
                    launch { warmUpWebProducts() }
                    startUpdateSystems()
                }
        }

        launch { jwtAuthWarmUpService.warmUpToken() }

        watchSsoEvents()
        launch { chatRequestServiceCoordinator.runChatRequestServices() }
        launch { chatBotStateController.activateDefaultBots() }

        launch { rootInteractor.printAccountAddresses() }

        launch { checkDevReset() }

        watchWeb3SummitEnd()
    }

    private suspend fun warmUpWebProducts() {
        web3SummitWarmUpService.warmUpWeb3SummitContent()
        if (FeatureOption.BROWSE_TAB.isEnabled) {
            exploreProductsService.warmUpExploreLoading()
        }
    }

    private fun watchWeb3SummitEnd() {
        observeWeb3SummitEnded()
            .filter { it }
            .onEach { postOnboardingFlow.openPostOnboarding() }
            .launchIn(this)
    }

    override val showDevResetPrompt = MutableStateFlow(false)

    override fun onDevResetStartOverClick() {
        launch { rootInteractor.clearAllAndClose() }
    }

    override fun onDevResetDismissClick() {
        showDevResetPrompt.disable()
    }

    private suspend fun checkDevReset() {
        if (rootInteractor.isDevResetNeeded()) {
            showDevResetPrompt.enable()
        }
    }

    private val _showDeeplinkOutcome = OneShotEventChannel<DeeplinkProcessingOutcome>()
    val showDeeplinkOutcome = _showDeeplinkOutcome.receiveAsFlow()

    fun handleDeepLink(uri: Uri) = launch {
        splashPassedObserver.awaitSplashPassed()
        val outcome = deeplinkHandler.handle(uri)
            .onFailure { Timber.e(it, "Failed to handle deeplink") }
            .flatten()
        _showDeeplinkOutcome.trySend(outcome)
    }

    private fun startUpdateSystems() {
        rootInteractor.startUpdateSystems().shareInBackground()
    }

    private fun watchSsoEvents() {
        if (FeatureOption.LINKED_DEVICES.isEnabled) {
            ssoService.watchSsoEvents().launchIn(this)
        }
    }
}
