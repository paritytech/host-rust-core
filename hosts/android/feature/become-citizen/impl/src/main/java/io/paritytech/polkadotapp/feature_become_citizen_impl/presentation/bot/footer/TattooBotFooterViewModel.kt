package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.bot.footer

import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.BuildConfig
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.common.utils.launchUnit
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.bot.TattooBotInteractor
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.bot.TattooBotState
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.dim.Dim1CommitmentHandler
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.BecomeCitizenRouter
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.bot.TattooBotContract
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.bot.model.TattooBotUiState
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatBotData
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatBotStateController
import io.paritytech.polkadotapp.feature_chats_api.presentation.model.ChatFeedPayload
import io.paritytech.polkadotapp.feature_people_api.presentation.mixin.DimSwitchMixin
import io.paritytech.polkadotapp.feature_people_api.presentation.mixin.create
import io.paritytech.polkadotapp.feature_upgrade_username_api.domain.model.UpgradeToFullUsernameState
import io.paritytech.polkadotapp.feature_upgrade_username_api.presentation.bot.toBotUi
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class TattooBotFooterViewModel @Inject constructor(
    private val router: BecomeCitizenRouter,
    private val chatBotStateController: ChatBotStateController,
    private val interactor: TattooBotInteractor,
    dimSwitchMixinFactory: DimSwitchMixin.Factory
) : BaseViewModel(), TattooBotContract {
    init {
        startObservers()
    }

    override val dimSwitchMixin = dimSwitchMixinFactory.create(
        currentDimId = Dim1CommitmentHandler.DIM_ID,
        onError = ::showError
    )

    override val state = combine(
        interactor.subscribeToBotState(),
        interactor.subscribeReadyToUpgradeUsername()
            .onStart { emit(UpgradeToFullUsernameState.NotReady) }
    ) { botState, readyToUpgradeUsername ->
        TattooBotUiState(
            botState = botState,
            upgradeUsernameUiState = readyToUpgradeUsername.toBotUi(),
            showFaq = BuildConfig.FAQ_ENABLED && botState.shouldShowFaq()
        )
    }.stateIn(this, started = SharingStarted.Eagerly, initialValue = TattooBotUiState())

    override fun proceedToTattooSelection() {
        router.openSelectAndReserveTattoo()
    }

    override fun provideVideoEvidence() {
        router.openProvideVideoEvidence()
    }

    override fun providePhotoEvidence() {
        router.openProvidePhotoEvidence()
    }

    override fun onUpgradeUsernameClick() {
        router.openUpgradeUsername()
    }

    override fun onNavigationToDim2Click() = launchUnit {
        activateAndOpenBot(ChatBotData.weeklyGame())
    }

    override fun onNavigationToMobRuleClick() = launchUnit {
        activateAndOpenBot(ChatBotData.mobRule())
    }

    private suspend fun activateAndOpenBot(botData: ChatBotData) {
        chatBotStateController.setActive(botData.id)

        router.back()
        router.openChatFeed(ChatFeedPayload.botChat(botData.id))
    }

    private fun startObservers() {
        launch { interactor.observeBotStepAndStartEvidenceUploader() }
    }

    private fun TattooBotState.shouldShowFaq(): Boolean {
        return when (this) {
            TattooBotState.INITIALIZING,
            TattooBotState.OTHER_DIM_COMMITMENT,
            TattooBotState.OTHER_DIM_IN_PROGRESS,
            TattooBotState.TATTOO_SELECTION,
            TattooBotState.WAITING_FOR_VIDEO_EVIDENCE,
            TattooBotState.WAITING_FOR_PHOTO_EVIDENCE -> true
            TattooBotState.WAITING_FOR_CONFIRMATION,
            TattooBotState.EVIDENCES_CONFIRMED,
            TattooBotState.REGISTERED_PERSON,
            TattooBotState.UNRECOVERABLE_ERROR -> false
        }
    }
}
