import Foundation
import FoundationExt
import UIKit
import PolkadotUI
import SubstrateSdk
import AsyncExtensions
import Keystore_iOS
import Operation_iOS
import StructuredConcurrency
import UIKitExt

protocol DIM2ChatExtending: ChatExtensionBotProtocol {
    var flowState: DIM2SharedFlowStateProtocol { get }
}

final class DIM2ChatExtension: ChatExtensionBot, ChatExtensionDelegateProvidable {
    // MARK: - Dependencies

    private let settings: ChatExtensionBotSettings
    private let interactor: DIM2ChatInteracting
    private let wireframe: WeeklyGameWireframeProtocol
    private let cameraPermissionService: CameraPermissionServicing
    private let applicationStateStreamFactory: ApplicationStateStreamFactory
    private let personActions: [ChatExtensionActions.ActionModel]
    private let logger: LoggerProtocol
    private var gameDepositContext: GameDepositProcessingContext?
    private var welcomeDeliveryTask: Task<Void, Never>?
    private var pendingDeliveryContext: ChatExtensionDiscoverContextProtocol?
    private var deferredTrackerTask: Task<Void, Never>?

    // MARK: - State

    private let footerContentConfiguration = AsyncCurrentValueSubject<(any HashableContentConfiguration)?>(nil)
    private let welcomeReadySubject = AsyncCurrentValueSubject<Bool>(false)
    private lazy var gameWidgetProvider = DIM2GameWidgetProvider(
        flowState: interactor.dim2FlowState,
        wireframe: wireframe
    )

    // MARK: - Tasks

    private var widgetStateTask: Task<Void, Error>?
    private var gameStatusTask: Task<Void, Error>?
    private var gameRegisterTask: Task<Void, Error>?
    private var fullUsernameClaimedTask: Task<Void, Error>?
    private var enableNotificationsTask: Task<Void, Error>?

    // MARK: - Protocol Conformance

    var flowState: DIM2SharedFlowStateProtocol {
        interactor.dim2FlowState
    }

    var delegate: ChatExtensionDelegate? {
        get {
            wireframe.registryDelegate
        }

        set {
            wireframe.registryDelegate = newValue
        }
    }

    // MARK: - Init

    init(
        settings: ChatExtensionBotSettings,
        interactor: DIM2ChatInteracting,
        wireframe: WeeklyGameWireframeProtocol,
        cameraPermissionService: CameraPermissionServicing,
        applicationStateStreamFactory: ApplicationStateStreamFactory,
        personActions: [ChatExtensionActions.ActionModel],
        logger: LoggerProtocol = Logger.shared
    ) {
        self.settings = settings
        self.interactor = interactor
        self.wireframe = wireframe
        self.cameraPermissionService = cameraPermissionService
        self.applicationStateStreamFactory = applicationStateStreamFactory
        self.personActions = personActions
        self.logger = logger

        super.init()
    }

    override func onTextMessage(
        _: Chat.LocalMessage,
        text _: String,
        context _: ChatExtensionProcessingContextProtocol
    ) async -> ChatExtension.ProcessingResult {
        .processed
    }
}

extension DIM2ChatExtension {
    static let welcomeInterMessagePause: Duration = .seconds(2)
    static let welcome1MarkerKey = "welcome1:\(DIM2ChatExtension.identifier)"
    static let welcomeIndexKey = "welcomeIndex:\(DIM2ChatExtension.identifier)"

    static var welcome1Content: Chat.LocalMessage.Content {
        #if FEATURE_PRIZES
            .staticTextImageContent(.init(
                text: String(localized: .WeeklyGame.w3SWelcome1),
                media: UIImage(resource: .WeeklyGame.prize1)
            ))
        #else
            .text(String(localized: .WeeklyGame.welcome1))
        #endif
    }

    fileprivate static var animatedWelcomes: [Chat.LocalMessage.Content] {
        #if FEATURE_PRIZES
            [
                .staticTextImageContent(.init(
                    text: String(localized: .WeeklyGame.w3SWelcome2),
                    media: UIImage(resource: .WeeklyGame.prize2)
                )),
                .staticTextImageContent(.init(
                    text: String(localized: .WeeklyGame.w3SWelcome3),
                    media: UIImage(resource: .WeeklyGame.prize3)
                )),
                .staticTextImageContent(.init(
                    text: String(localized: .WeeklyGame.w3SWelcome4),
                    media: UIImage(resource: .WeeklyGame.prize4)
                )),
                .staticTextImageContent(.init(
                    text: String(localized: .WeeklyGame.w3SWelcome5),
                    media: UIImage(resource: .WeeklyGame.prize5)
                )),
                .staticTextImageContent(.init(
                    text: String(localized: .WeeklyGame.w3SWelcome6),
                    media: UIImage(resource: .WeeklyGame.prize6)
                ))
            ]
        #else
            [
                .text(String(localized: .WeeklyGame.welcome2)),
                .staticTextImageContent(.init(
                    text: String(localized: .WeeklyGame.welcome3),
                    media: UIImage(resource: .WeeklyGame.welcome2)
                )),
                .staticTextImageContent(.init(
                    text: String(localized: .WeeklyGame.welcome4),
                    media: UIImage(resource: .WeeklyGame.welcome3)
                )),
                .text(String(localized: .WeeklyGame.welcome5)),
                .text(String(localized: .WeeklyGame.welcome6)),
                .text(String(localized: .WeeklyGame.welcome7))
            ]
        #endif
    }

    private func deliverAnimatedWelcomesIfNeeded(
        _ context: ChatExtensionDiscoverContextProtocol
    ) async {
        defer { welcomeReadySubject.send(true) }

        guard await !context.hasDeliveredWelcomeMessages(for: self) else { return }

        let contents = Self.animatedWelcomes
        let startIndex = SettingsManager.shared.integer(for: Self.welcomeIndexKey) ?? 0

        for offset in startIndex ..< contents.count {
            try? await Task.sleep(for: Self.welcomeInterMessagePause)

            do {
                _ = try await context.sendNewMessage(
                    from: self,
                    newContent: contents[offset],
                    messageDeliveryDelay: .immediate
                )
                SettingsManager.shared.set(value: offset + 1, for: Self.welcomeIndexKey)
            } catch {
                logger.error("Welcome message \(offset + 2) failed: \(error)")
                return
            }
        }

        await context.markWelcomeMessagesDelivered(for: self)
    }
}

// MARK: - ChatExtensionBotProtocol

extension DIM2ChatExtension: DIM2ChatExtending {
    nonisolated static let identifier: ChatExtension.Id = "WeeklyGame"

    var identifier: ChatExtension.Id { Self.identifier }

    var peerMetadata: Chat.PeerMetadata {
        #if FEATURE_PRIZES
            let name = String(localized: .WeeklyGame.polkadotPrizesChatName)
            let icon = Chat.PeerMetadata.Icon.image(UIImage(resource: .WeeklyGame.prizesIcon).pngData())
        #else
            let name = String(localized: .WeeklyGame.chatName)
            let icon = Chat.PeerMetadata.Icon.bot
        #endif

        return Chat.PeerMetadata(
            name: name,
            contactSource: .chat,
            icon: icon,
            input: .empty,
            moreActions: [.custom(makeGameAlarmAction())]
        )
    }

    func deliverAutomaticMessages(_ context: ChatExtensionDiscoverContextProtocol) {
        #if FEATURE_DIMS_FULL
            guard settings.isEnabled(extId: identifier) else {
                return
            }
        #endif

        pendingDeliveryContext = context

        Task { [interactor, welcomeReadySubject, weak self] in
            if let self {
                let alreadyDelivered = await context.hasDeliveredWelcomeMessages(for: self)
                let welcome1Sent = SettingsManager.shared.bool(for: Self.welcome1MarkerKey) ?? false
                if !alreadyDelivered, !welcome1Sent {
                    do {
                        _ = try await context.sendNewMessage(
                            from: self,
                            newContent: Self.welcome1Content,
                            messageDeliveryDelay: .immediate
                        )
                        SettingsManager.shared.set(value: true, for: Self.welcome1MarkerKey)
                    } catch {
                        logger.error("Welcome 1 send failed: \(error)")
                    }
                }

                if alreadyDelivered {
                    welcomeReadySubject.send(true)
                }
            }
            await interactor.setup()
        }

        setupEnableNotificationTracking()

        deferredTrackerTask?.cancel()
        deferredTrackerTask = Task { [weak self, welcomeReadySubject] in
            for await ready in welcomeReadySubject where ready {
                break
            }
            guard let self else { return }
            setupFooterStateTracking()
            setupGameStatusTracking(with: context)
            setupGameRegistrationTracking(with: context)
            setupFullUsernameClaimedTracking(with: context)
            gameDepositContext = GameDepositProcessingContext(context: context)
            gameWidgetProvider.setup()
        }
    }

    func process(
        action _: Chat.Action,
        context _: ChatExtensionActionContextProtocol
    ) async {
        // Actions are handled via widget callbacks
    }

    func attach(presentationView: ControllerBackedProtocol) {
        Task { @MainActor [wireframe] in
            wireframe.view = presentationView
        }

        guard welcomeDeliveryTask == nil, let context = pendingDeliveryContext else { return }
        welcomeDeliveryTask = Task { [weak self] in
            await self?.deliverAnimatedWelcomesIfNeeded(context)
            self?.welcomeDeliveryTask = nil
        }
    }
}

extension DIM2ChatExtension: ChatExtensionActionProvidable {
    func contentConfiguration() async throws -> AnyAsyncSequence<(any HashableContentConfiguration)?> {
        footerContentConfiguration
            .removeDuplicates { lhs, rhs in
                switch (lhs, rhs) {
                case (nil, nil):
                    true
                case let (lhs?, rhs?):
                    AnyHashable(lhs) == AnyHashable(rhs)
                default:
                    false
                }
            }
            .eraseToAnyAsyncSequence()
    }
}

extension DIM2ChatExtension: ChatExtensionWidgetProvidable {
    func widgetConfigurationStream() async throws -> AnyAsyncSequence<(any HashableContentConfiguration)?> {
        let widgetConfigurationStream = try await gameWidgetProvider.widgetConfigurationStream()

        return widgetConfigurationStream
            .removeDuplicates { lhs, rhs in
                switch (lhs, rhs) {
                case (nil, nil):
                    true
                case let (lhs?, rhs?):
                    AnyHashable(lhs) == AnyHashable(rhs)
                default:
                    false
                }
            }
            .eraseToAnyAsyncSequence()
    }
}

extension DIM2ChatExtension {
    func entryRoute(for model: ChatOpenModel) async -> ChatExtensionEntryRoute {
        let gameInfo = await interactor.getGameInfo()

        guard gameInfo?.isGameRoomAvailable(availabilityInterval: .secondsInMinute) == true else {
            return .chat(model)
        }

        return .deepLink(AppConfig.DeepLink.game())
    }
}

private extension DIM2ChatExtension {
    func setupGameStatusTracking(with context: ChatExtensionDiscoverContextProtocol) {
        gameStatusTask?.cancel()
        gameStatusTask = Task { [interactor, logger] in
            do {
                let processingContext = GameResultProcessingContext(context: context, logger: logger)
                try await processingContext.process(
                    results: interactor.observeGameResults(),
                    sender: self
                )
            } catch {
                logger.error("Game state task failed: \(error)")
            }
        }
    }

    func setupGameRegistrationTracking(with context: ChatExtensionDiscoverContextProtocol) {
        gameRegisterTask?.cancel()
        gameRegisterTask = Task { [interactor, logger] in
            do {
                let processingContext = GameRegistrationContext(context: context)
                try await processingContext.process(
                    results: interactor.observeGameRegistration(),
                    sender: self
                )
            } catch {
                logger.debug("Game registration task failed: \(error)")
            }
        }
    }

    func setupFullUsernameClaimedTracking(with context: ChatExtensionDiscoverContextProtocol) {
        fullUsernameClaimedTask?.cancel()
        fullUsernameClaimedTask = Task { [interactor, logger] in
            do {
                let processingContext = FullUsernameClaimedContext(context: context)
                try await processingContext.process(
                    contentSequence: interactor.observeFullUsernameClaimed(),
                    sender: self
                )
            } catch {
                logger.error("Full username claimed task failed: \(error)")
            }
        }
    }

    func setupEnableNotificationTracking() {
        enableNotificationsTask?.cancel()
        enableNotificationsTask = Task { [interactor, logger] in
            do {
                for try await model in interactor.observeEnableNotifications() {
                    await MainActor.run { [weak wireframe] in
                        let viewModel = EnableNotificationsModel { _, granted in
                            model.callback(granted)
                            wireframe?.dismiss(nil)
                        }

                        wireframe?.showEnableNotifications(viewModel)
                    }
                }
            } catch {
                logger.error("Enable notification task failed: \(error)")
            }
        }
    }
}

private extension DIM2ChatExtension {
    func setupFooterStateTracking() {
        widgetStateTask?.cancel()
        widgetStateTask = Task { [weak self] in
            guard let self else { return }

            for try await state in interactor.observeWidgetState() {
                await MainActor.run { [footerContentConfiguration] in
                    let config = self.mapToFooterConfiguration(state)
                    self.logger.debug("Yielding config: \(String(describing: config))")
                    footerContentConfiguration.send(config)
                }
            }
        }
    }

    @MainActor
    func mapToFooterConfiguration(_ state: DIM2WidgetState) -> (any HashableContentConfiguration)? {
        guard let switchState = state.switchToDIM1 else {
            return mapToGameWidgetConfiguration(state).configuration()
        }

        return DIM2FooterConfiguration.switchDIM(inProgress: switchState.inProgress) { [weak self] in
            Task { @MainActor in
                self?.handleSwitchDimAction(switchPossible: switchState.possible)
            }
        }
    }

    @MainActor
    func mapToGameWidgetConfiguration(_ state: DIM2WidgetState) -> GameWidgetConfigProvider {
        let actions = mapFooterActions(from: state)
        let upgradeUsername = mapUpgradeUsername(from: state)

        return GameWidgetConfigProvider(
            model: .init(
                gameState: state.gameState.map { mapGameState($0) },
                isLoading: state.isLoading,
                isRegisterEnabled: state.gameRegistrationState != .openingSoon,
                actionViewModels: actions,
                upgradeUsername: upgradeUsername,
                onActionContext: AnyHashable(
                    GameWidgetConfigContext(
                        gameRegistrationState: state.gameRegistrationState,
                        personRegistrationState: state.personRegistrationState
                    )
                )
            ),
            onAction: { [weak self, logger] action, contextWrapper in
                // we add manual dependency on context instead of state
                // since state might change but provider stays the same
                // that might result in wrong action being handled
                guard let context = contextWrapper.base as? GameWidgetConfigContext else {
                    logger.error("Unexpected context: \(contextWrapper.base)")
                    return
                }

                self?.handleWidgetAction(action, context: context)
            }
        )
    }

    func mapUpgradeUsername(from state: DIM2WidgetState) -> GameWidgetConfigProvider.UpgradeUsernameData? {
        switch state.personRegistrationState {
        case let .needsFullUsername(upgradeData):
            GameWidgetConfigProvider.UpgradeUsernameData(
                liteUsername: upgradeData.displayLiteUsername,
                suggestedFullUsername: upgradeData.suggestedFullUsername
            )
        case .notGamePerson,
             .gamePerson:
            nil
        }
    }

    func mapFooterActions(from state: DIM2WidgetState) -> [ChatMessageActionView.ViewModel] {
        switch state.personRegistrationState {
        case .gamePerson:
            personActions.map { action in
                ChatMessageActionView.ViewModel(
                    title: action.title,
                    subtitle: action.subtitle,
                    buttonTitle: String(localized: .ChatExtension.polkadotPeerActionOpen)
                ) { [wireframe] in
                    Task { @MainActor in
                        wireframe.openChatWithExtension(action.identifier)
                    }
                }
            }
        case .needsFullUsername,
             .notGamePerson:
            []
        }
    }

    func mapGameState(_ state: DIM2WidgetState.GameState) -> GameWidgetConfigProvider.GameState {
        switch state {
        case let .register(gameDate):
            .register(gameDate: gameDate)
        case let .registered(gameDate):
            .registered(gameDate: gameDate)
        case let .starting(gameDate):
            .starting(gameDate: gameDate)
        }
    }
}

// MARK: - Widget Action Handling

private extension DIM2ChatExtension {
    @MainActor
    func handleWidgetAction(_ action: GameWidgetConfigProvider.Action, context: GameWidgetConfigContext) {
        switch action {
        case .register:
            handleRegisterAction(for: context.gameRegistrationState)
        case .upgradeUsername:
            handleUpgradeUsernameAction(for: context.personRegistrationState)
        }
    }

    @MainActor
    func handleRegisterAction(for state: DIM2WidgetState.GameRegistrationState) {
        switch state {
        case .unknown:
            logger.error("No registration info available")
        case .openingSoon:
            logger.debug("Registration not open yet — ignoring register action")
        case .requiresDeposit,
             .canRegister:
            register(for: state)
        }
    }

    @MainActor
    func handleUpgradeUsernameAction(for state: DIM2WidgetState.PersonRegistrationState) {
        guard case let .needsFullUsername(upgradeData) = state else {
            logger.error("Unexpected state during handling username upgrade: \(state)")
            return
        }

        wireframe.showUpgradeUsername(upgradeData)
    }

    @MainActor
    func register(for state: DIM2WidgetState.GameRegistrationState) {
        Task { [weak self] in
            await self?.performRegistration(for: state)
        }
    }

    @MainActor
    func performRegistration(for state: DIM2WidgetState.GameRegistrationState) async {
        await requestCameraPermissionIfNeeded()

        do {
            try await interactor.register { [weak self] error in
                await self?.resolve(error: error, for: state) ?? .cancel
            }
        } catch {
            logger.error("Registration failed: \(error)")
            wireframe.present(error: error)
        }
    }

    @MainActor
    func requestCameraPermissionIfNeeded() async {
        let permission = await cameraPermissionService.requestPermission()
        guard permission == .denied else { return }
        await waitForCameraPermissionAlert()
    }

    @MainActor
    func waitForCameraPermissionAlert() async {
        let shouldWaitForActive = await withCheckedContinuation { [wireframe] continuation in
            wireframe.askOpenApplicationSettings(
                with: String(localized: .Game.gameCameraPermissionRegistrationMessage),
                title: String(localized: .Game.gameCameraPermissionTitle),
                from: wireframe.view,
                completion: { result in
                    continuation.resume(returning: result == .openedSettings)
                }
            )
        }

        guard shouldWaitForActive else {
            return
        }

        let activeEvents = applicationStateStreamFactory.stream(for: .didBecomeActive)

        for await _ in activeEvents {
            return
        }
    }

    @MainActor
    func resolve(
        error: DIM2RegistrationError,
        for state: DIM2WidgetState.GameRegistrationState
    ) async -> DIM2RegistrationDecision {
        switch error {
        case .invitationServiceUnavailable:
            await resolveInvitationUnavailable(for: state)
        }
    }

    @MainActor
    func resolveInvitationUnavailable(
        for state: DIM2WidgetState.GameRegistrationState
    ) async -> DIM2RegistrationDecision {
        let wantsDeposit = await waitInvitationUnavailableChoice()
        guard wantsDeposit else {
            return .cancel
        }

        do {
            let processed = try await runDepositFlow(for: state)
            return processed ? .skipInvitation : .cancel
        } catch {
            wireframe.present(error: error)
            return .cancel
        }
    }

    @MainActor
    private func waitInvitationUnavailableChoice() async -> Bool {
        do {
            return try await withCheckedThrowingContinuation { continuation in
                let guarded = CheckedContinuationGuard(continuation)
                wireframe.showInvitationServiceUnavailable(
                    depositHandler: { guarded.resume(returning: true) },
                    cancelHandler: { guarded.resume(returning: false) }
                )
            }
        } catch {
            return false
        }
    }

    @MainActor
    func runDepositFlow(for state: DIM2WidgetState.GameRegistrationState) async throws -> Bool {
        guard case let .requiresDeposit(depositInfo) = state else {
            return true
        }

        guard !depositInfo.neededAmount.isZero else {
            logger.error("Zero deposit amount")
            return false
        }

        guard let confirmedDeposit = await requestDeposit(amount: depositInfo.neededAmount) else {
            return false
        }

        guard let processingContext = gameDepositContext else {
            return false
        }

        try await processingContext.process(deposit: confirmedDeposit, sender: self)
        return true
    }

    @MainActor
    private func requestDeposit(amount: Balance) async -> ConfirmedDeposit? {
        do {
            return try await withCheckedThrowingContinuation { continuation in
                let guarded = CheckedContinuationGuard<ConfirmedDeposit?>(continuation)
                let depositModel = GameDepositRequiredModel(
                    depositHandler: { [weak self] in
                        self?.wireframe.dismiss { [weak self] in
                            self?.requestDepositConfirmation(amount: amount, guarded: guarded)
                        }
                    },
                    cancelHandler: { guarded.resume(returning: nil) }
                )
                wireframe.showDeposit(amount, model: depositModel)
            }
        } catch {
            return nil
        }
    }

    @MainActor
    private func requestDepositConfirmation(
        amount: Balance,
        guarded: CheckedContinuationGuard<ConfirmedDeposit?>
    ) {
        let confirmModel = ConfirmDepositModel(
            confirmHandler: { [weak self] confirmed in
                self?.wireframe.dismiss(nil)
                guarded.resume(returning: confirmed)
            },
            cancelHandler: { guarded.resume(returning: nil) }
        )

        wireframe.showDepositConfirmation(amount, model: confirmModel)
    }
}

private extension DIM2ChatExtension {
    nonisolated func makeGameAlarmAction() -> Chat.CustomPeerAction {
        let titleProvider = {
            let current = SettingsManager.shared.gameAlarmTimingSeconds
            let option = String(localized: .Game.gameAlarmSettingsAlertOption(sec: current))
            return String(localized: .Game.gameAlarmSettingsAlertRow(selectedOption: option))
        }

        let handler: () -> Void = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let model = GameAlarmSettingsModel { [weak self] in
                    Task { await self?.interactor.rescheduleGameAlarm() }
                }
                self.wireframe.showGameAlarmSettings(model: model)
            }
        }

        return Chat.CustomPeerAction(
            titleProvider: titleProvider,
            image: .WeeklyGame.alarm,
            handler: handler
        )
    }
}

extension DIM2ChatExtension {
    enum DimSwitchingError: Error, ErrorContentConvertible {
        case unavailable

        func toErrorContent() -> ErrorContent {
            .init(
                title: String(localized: .ChatExtension.dimSwitchErrorTitle),
                message: String(localized: .ChatExtension.dim2SwitchErrorMessage)
            )
        }
    }

    @MainActor
    func handleSwitchDimAction(switchPossible possible: Bool) {
        if possible {
            wireframe.showSwitchDIMConfirmation {
                Task { [weak self] in
                    try await self?.interactor.switchToCurrentDim()
                }
            }
        } else {
            wireframe.present(error: DimSwitchingError.unavailable)
        }
    }
}
