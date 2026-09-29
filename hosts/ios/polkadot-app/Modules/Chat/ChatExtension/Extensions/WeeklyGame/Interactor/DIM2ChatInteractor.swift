import Foundation
import AlarmKit
import SubstrateSdk
import AsyncExtensions
import AsyncAlgorithms
import PolkadotUI
import Operation_iOS
import Keystore_iOS
import EventKit
import Individuality
import BackgroundExecution
import StructuredConcurrency

final class DIM2ChatInteractor {
    let dependencies: DIM2Depending
    let logger: LoggerProtocol

    private let gameVoteRepositoryFactory: GameVoteRepositoryMaking
    private let backgroundExecutor: BackgroundExecuting

    // Calendar & Notifications
    private let gameCalendarService: GameCalendarServicing
    private let gameNotificationsService: GameNotificationServicing

    // Invitations
    private let invitationRegistrationService: GameInvitationRegistering

    // Balance
    private let balanceTrackingFactory: BalanceTrackingFactoryProtocol
    private let requiredBalanceOperationFactory: GamePalletBalanceFactoryProtocol

    // Remaining games
    private let remainingGamesOperationFactory: RemainingGamesOperationMaking

    // Airdrop
    private let airdropRegistrationStore: AirdropRegistrationStoring
    private let localNetworkPermissionService: LocalNetworkPermissionServicing
    private let walletRepo: WalletManagerRepositoryProtocol

    // MARK: - State Actor

    var dim2FlowState: DIM2SharedFlowStateProtocol {
        dependencies.sharedState
    }

    private let state: DIM2ChatInteractorState

    // MARK: - Subjects for Extension Streams

    private let widgetStateSubject = AsyncCurrentValueSubject<DIM2WidgetState?>(nil)
    private let depositSubject = AsyncCurrentValueSubject<[ConfirmedDeposit]>([])
    private let gameRegistrationSubject = AsyncCurrentValueSubject<GameInfo?>(nil)
    private let gameHistorySubject = AsyncCurrentValueSubject<GameHistory?>(nil)
    private let fullUsernameClaimedSubject = AsyncPassthroughSubject<FullUsernameClaimedMessageDecoder.Content>()
    private let personhoodRegisteredSubject = AsyncPassthroughSubject<PeoplePallet.PersonalId>()
    private let enableNotificationsSubject = AsyncPassthroughSubject<DIM2EnableNotifications>()

    // MARK: - State Observation Tasks

    private var gameInfoTask: Task<Void, Never>?
    private var scoreInfoTask: Task<Void, Never>?
    private var gameScheduleTask: Task<Void, Never>?
    private var gameHistoryTask: Task<Void, Never>?
    private var registeredDataTask: Task<Void, Never>?
    private var remoteStateTask: Task<Void, Never>?
    private var airdropGateTask: Task<Void, Never>?
    private var airdropGateSubscribedIndex: GamePallet.GameIndex?

    // MARK: - Init

    init(
        dependencies: DIM2Depending,
        gameVoteRepositoryFactory: GameVoteRepositoryMaking,
        gameCalendarService: GameCalendarServicing,
        gameNotificationsService: GameNotificationServicing,
        invitationRegistrationService: GameInvitationRegistering,
        balanceTrackingFactory: BalanceTrackingFactoryProtocol,
        requiredBalanceOperationFactory: GamePalletBalanceFactoryProtocol,
        remainingGamesOperationFactory: RemainingGamesOperationMaking,
        backgroundExecutor: BackgroundExecuting,
        airdropRegistrationStore: AirdropRegistrationStoring = AirdropRegistrationStore(),
        localNetworkPermissionService: LocalNetworkPermissionServicing,
        walletRepo: WalletManagerRepositoryProtocol = .shared,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.dependencies = dependencies
        self.gameVoteRepositoryFactory = gameVoteRepositoryFactory
        self.gameCalendarService = gameCalendarService
        self.gameNotificationsService = gameNotificationsService
        self.invitationRegistrationService = invitationRegistrationService
        self.balanceTrackingFactory = balanceTrackingFactory
        self.requiredBalanceOperationFactory = requiredBalanceOperationFactory
        self.remainingGamesOperationFactory = remainingGamesOperationFactory
        self.backgroundExecutor = backgroundExecutor
        self.airdropRegistrationStore = airdropRegistrationStore
        self.localNetworkPermissionService = localNetworkPermissionService
        self.walletRepo = walletRepo
        self.logger = logger
        state = DIM2ChatInteractorState()
    }

    deinit {
        cancelObservationTasks()
    }

    private func cancelObservationTasks() {
        gameInfoTask?.cancel()
        scoreInfoTask?.cancel()
        gameScheduleTask?.cancel()
        gameHistoryTask?.cancel()
        registeredDataTask?.cancel()
        remoteStateTask?.cancel()
        airdropGateTask?.cancel()
        airdropGateSubscribedIndex = nil
    }
}

// MARK: - DIM2ChatInteracting

extension DIM2ChatInteractor: DIM2ChatInteracting {
    func setup() async {
        await setupStateCallbacks()

        dependencies.setup()

        startStateObservation()
        startObservingCommonStateStore()
    }

    // MARK: - Observation Streams

    func observeWidgetState() -> AnyAsyncSequence<DIM2WidgetState> {
        widgetStateSubject
            .compactMap { $0 }
            .removeDuplicates()
            .eraseToAnyAsyncSequence()
    }

    func observeGameRegistration() -> AnyAsyncSequence<GameInfo> {
        gameRegistrationSubject
            .compactMap { $0 }
            .eraseToAnyAsyncSequence()
    }

    func observeGameHistory() -> AnyAsyncSequence<GameHistory?> {
        gameHistorySubject.eraseToAnyAsyncSequence()
    }

    func observeDeposits() -> AnyAsyncSequence<[GameDepositMessageDecoder.Deposit]> {
        depositSubject
            .map {
                $0.map {
                    GameDepositMessageDecoder.Deposit(
                        amount: $0.amount,
                        assetId: $0.chainAssetId.assetId
                    )
                }
            }
            .eraseToAnyAsyncSequence()
    }

    func observeFullUsernameClaimed() -> AnyAsyncSequence<FullUsernameClaimedMessageDecoder.Content> {
        fullUsernameClaimedSubject
            .removeDuplicates()
            .eraseToAnyAsyncSequence()
    }

    func observePersonhoodRegistered() -> AnyAsyncSequence<PeoplePallet.PersonalId> {
        personhoodRegisteredSubject
            .removeDuplicates()
            .eraseToAnyAsyncSequence()
    }

    func observeEnableNotifications() -> AnyAsyncSequence<DIM2EnableNotifications> {
        enableNotificationsSubject.eraseToAnyAsyncSequence()
    }

    // MARK: - Queries

    func getScoreInfo() async -> ScoreInfo? {
        await state.scoreInfo
    }

    func getGameInfo() async -> GameInfo? {
        await state.gameInfo
    }

    func fetchRemainingGamesResult(atBlock block: Data?) async throws -> RemainingGamesResult? {
        guard let accountOrPerson = await state.getAccountOrPerson() else {
            logger.error("Missing account or person")
            return nil
        }
        return try await remainingGamesOperationFactory.fetchResult(
            for: accountOrPerson,
            atBlock: block
        )
    }

    func hasVotes(forGame index: UInt32) async throws -> Bool {
        let voteNumber = try await gameVoteRepositoryFactory.repository(forGame: index)
            .fetchCountOperation()
            .asyncExecute()
        return voteNumber != 0
    }

    // MARK: - Mutations

    func register(decisionHandler: @escaping DIM2RegistrationDecisionHandler) async throws {
        guard await state.gameInfo?.gameDate != nil else {
            return
        }

        await state.setLoading(true)

        do {
            let mode = await state.makeRegisterMode()
            switch mode {
            case let .player(isCredible):
                if isCredible {
                    try await registerForGame(with: mode)
                } else {
                    try await registerWithInvitation(decisionHandler: decisionHandler)
                }
            case .scoreAlias:
                try await registerForGame(with: mode)
            }
            await state.setLoading(false)
        } catch {
            await state.setLoading(false)
            throw error
        }
    }

    func confirmDeposit(_ deposit: ConfirmedDeposit) {
        depositSubject.send([deposit])
    }

    func rescheduleGameAlarm() async {
        let gameInfo = await state.gameInfo
        gameNotificationsService.scheduleGameStartNotifications(for: gameInfo)
    }

    func switchToCurrentDim() async throws {
        guard await !(state.flakeOutInProgress) else {
            return
        }

        guard let candidate = await state.candidate else {
            return
        }

        do {
            let terminationService = try dim2FlowState.createTattooTerminationService(candidate: candidate)
            await state.updateOffboard(inProgress: true)
            _ = try await terminationService.flakeOut().asyncExecute()
            await state.updateOffboard(inProgress: false)
        } catch {
            logger.error("Tattoo termination failed: \(error)")
            await state.updateOffboard(inProgress: false)
            throw error
        }
    }
}

// MARK: - State Observation

private extension DIM2ChatInteractor {
    func startStateObservation() {
        registeredDataTask = Task { [dim2FlowState, logger, weak self] in
            do {
                for try await personData in dim2FlowState.personDataStore.observe() {
                    logger.debug("Person data: \(String(describing: personData))")
                    await self?.handleRegisteredDataUpdate(registeredData: personData?.makeRegisteredData())
                    await self?.handleAccountOrPersonUpdate(accountOrPerson: personData?.makeAccountOrPerson())
                }
            } catch {
                logger.error("Person data subscription failed: \(error)")
            }
        }

        gameInfoTask = Task { [dim2FlowState, logger, weak self] in
            do {
                for try await gameInfo in dim2FlowState.gameSyncService.observe() {
                    logger.debug("Game info: \(String(describing: gameInfo))")
                    await self?.handleGameInfoUpdate(gameInfo: gameInfo)
                }
            } catch {
                logger.error("Game info subscription failed: \(error)")
            }
        }

        scoreInfoTask = Task { [state, dim2FlowState, logger] in
            do {
                for try await scoreInfo in dim2FlowState.scoreSyncService.observe() {
                    logger.debug("Score info: \(String(describing: scoreInfo))")
                    await state.updateScoreInfo(scoreInfo)
                }
            } catch {
                logger.error("Score info subscription failed: \(error)")
            }
        }

        gameScheduleTask = Task { [weak self, dim2FlowState, logger] in
            do {
                for try await schedule in dim2FlowState.gameScheduleSyncService.observe() {
                    logger.debug("Schedule: \(String(describing: schedule))")
                    await self?.handleGameScheduleUpdate(gameSchedule: schedule)
                }
            } catch {
                logger.error("Schedule subscription failed: \(error)")
            }
        }

        gameHistoryTask = Task { [weak self, dim2FlowState, logger] in
            do {
                for try await history in dim2FlowState.gameHistorySyncService.observe() {
                    logger.debug("Game history: \(String(describing: history))")
                    await self?.handleGameHistoryUpdate(gameHistory: history)
                }
            } catch {
                logger.error("Game history subscription failed: \(error)")
            }
        }
    }

    func setupStateCallbacks() async {
        await state.setOnWidgetUpdate { [weak self, logger] newState in
            logger.debug("New widget state: \(String(describing: newState))")
            self?.widgetStateSubject.send(newState)
        }

        await state.setOnDepositTaskStart { [weak self] in
            self?.createDepositTask()
        }
    }
}

// MARK: - State Update Handlers

private extension DIM2ChatInteractor {
    func handleRegisteredDataUpdate(registeredData: People.RegisteredData?) async {
        await state.updateRegisteredData(registeredData)
        updatePersonRegistrationState(registeredData: registeredData)
        updateUsernameClaimedState(registeredData: registeredData)
    }

    func handleAccountOrPersonUpdate(accountOrPerson: GamePallet.AccountOrPerson?) async {
        await state.updateAccountOrPerson(accountOrPerson)
    }

    func handleGameInfoUpdate(gameInfo: GameInfo?) async {
        await state.updateGameInfo(gameInfo)

        gameNotificationsService.scheduleGameStartNotifications(for: gameInfo)
        let gameSchedule = await state.gameSchedule
        gameNotificationsService.scheduleRegistrationStartNotifications(
            for: gameSchedule,
            currentGameInfo: gameInfo
        )
        gameNotificationsService.scheduleRegistrationOpenNotifications(for: gameSchedule)
        await ensureCalendarEventAdded()
        await ensureAirdropGateSubscription()
    }

    func ensureAirdropGateSubscription() async {
        let gameIndex = await state.airdropRegistrationGateGameIndex()

        guard let gameIndex else {
            airdropGateTask?.cancel()
            airdropGateTask = nil
            airdropGateSubscribedIndex = nil
            return
        }

        guard airdropGateSubscribedIndex != gameIndex else { return }

        airdropGateTask?.cancel()
        airdropGateSubscribedIndex = gameIndex
        logger.debug("[GameDebug] airdrop gate: subscribing to event status gameIndex=\(gameIndex)")

        airdropGateTask = Task { [airdropService = dim2FlowState.airdropService, state, logger] in
            while !Task.isCancelled {
                for await status in airdropService.subscribeEventStatus(forGameIndex: gameIndex) {
                    guard !Task.isCancelled else { return }
                    if case .registering = status {
                        logger.debug("[GameDebug] airdrop gate: registering → enable register gameIndex=\(gameIndex)")
                        await state.confirmAirdropRegistering(forGameIndex: gameIndex)
                        return
                    }
                }
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    func handleGameScheduleUpdate(gameSchedule: GameSchedule?) async {
        await state.updateGameSchedule(gameSchedule)
        let gameInfo = await state.gameInfo
        gameNotificationsService.scheduleRegistrationStartNotifications(
            for: gameSchedule,
            currentGameInfo: gameInfo
        )
        gameNotificationsService.scheduleRegistrationOpenNotifications(for: gameSchedule)
    }

    func handleGameHistoryUpdate(gameHistory: GameHistory?) async {
        await state.updateGameHistory(gameHistory)
        gameHistorySubject.send(gameHistory)
    }

    func updatePersonRegistrationState(registeredData: People.RegisteredData?) {
        guard
            let registeredData,
            case .game = registeredData.source else {
            return
        }

        personhoodRegisteredSubject.send(registeredData.personId)
    }

    func updateUsernameClaimedState(registeredData: People.RegisteredData?) {
        guard
            let registeredData,
            case .game = registeredData.source,
            let fullUsername = registeredData.fullUsername else {
            return
        }

        let content = FullUsernameClaimedMessageDecoder.Content(
            liteUsername: registeredData.liteUsername,
            fullUsername: fullUsername
        )

        fullUsernameClaimedSubject.send(content)
    }

    func requestCalendarAccessAfterRegistration() async {
        guard !hasActiveCalendarReminder() else {
            return
        }

        let calendarEvent = await state.calendarEvent
        await requestCalendarAccessAndAddEvent(calendarEvent)
    }

    func ensureCalendarEventAdded() async {
        guard
            let calendarEvent = await state.calendarEvent,
            !hasActiveCalendarReminder()
        else {
            return
        }

        await requestCalendarAccessAndAddEvent(calendarEvent)
    }

    func requestCalendarAccessAndAddEvent(_ calendarEvent: CalendarGameModel?) async {
        guard await gameCalendarService.requestWriteAccess() else {
            logger.error("Calendar write access denied")
            return
        }

        guard let calendarEvent else {
            return
        }

        addCalendarEvent(calendarEvent)
    }

    func addCalendarEvent(_ calendarEvent: CalendarGameModel) {
        do {
            try gameCalendarService.addEvent(for: calendarEvent)
        } catch {
            logger.error("Failed to add event to calendar: \(error)")
            return
        }

        gameCalendarService.saveReminder(
            GameCalendarReminder(
                title: calendarEvent.title,
                startDate: calendarEvent.startDate,
                endDate: calendarEvent.endDate
            )
        )
    }

    func hasActiveCalendarReminder() -> Bool {
        guard let reminder = gameCalendarService.savedReminder() else {
            return false
        }

        guard Date() < reminder.endDate else {
            gameCalendarService.clearReminder()
            return false
        }

        return true
    }
}

// MARK: - Common State Observation

private extension DIM2ChatInteractor {
    func startObservingCommonStateStore() {
        remoteStateTask?.cancel()
        remoteStateTask = Task { [dim2FlowState, state, logger] in
            do {
                for try await remoteState in dim2FlowState.commonStateStore.observe() {
                    logger.debug("Remote state: \(String(describing: remoteState))")
                    await state.updateCandidate(remoteState?.candidate)
                }
            } catch {
                logger.error("Common state observation failed: \(error)")
            }
        }
    }
}

// MARK: - Registration Logic

private extension DIM2ChatInteractor {
    func registerWithInvitation(
        decisionHandler: @escaping DIM2RegistrationDecisionHandler
    ) async throws {
        logger.debug("Will register for a game with invitation")

        let airdrop = await resolveAirdropProof()
        do {
            try await backgroundExecutor.execute { [self] in
                try await markStallActivity("Invitation game registration") {
                    try await invitationRegistrationService.register(airdrop: airdrop)
                }
            }
            await handlePostRegistrationSuccess()
            await persistAirdropRegistration(airdrop: airdrop, usesScoreAlias: false)
            logger.debug(
                "[GameDebug] registerWithInvitation SUCCESS airdrop=\(airdrop != nil ? "present" : "nil")"
            )
        } catch {
            logger.error(
                "[GameDebug] registerWithInvitation FAILED airdrop=\(airdrop != nil ? "present" : "nil") "
                    + "errorType=\(type(of: error)) error=\(error)"
            )

            let decision = await decisionHandler(
                .invitationServiceUnavailable(underlying: error)
            )

            switch decision {
            case .skipInvitation:
                let mode = await state.makeRegisterMode()
                try await registerForGame(with: mode)
            case .cancel:
                logger.debug("Registration cancelled by user")
            }
        }
    }

    func registerForGame(with mode: GameRegisterMode) async throws {
        let registrationService = try dim2FlowState.setupGameRegistrationService()
        let airdrop = await resolveAirdropProof()
        do {
            try await backgroundExecutor.execute { [self] in
                let result = try await markStallActivity("Game registration") {
                    try await markStallRegion("Registration") {
                        try await registrationService.registerForGame(with: mode, airdrop: airdrop).asyncExecute()
                    }
                }

                switch result.status {
                case let .success(successExtrinsic):
                    logger.debug(
                        "[GameDebug] registerForGame SUCCESS hash=\(successExtrinsic.extrinsicHash) "
                            + "airdrop=\(airdrop != nil ? "present" : "nil")"
                    )
                    await handlePostRegistrationSuccess()
                    let usesScoreAlias = if case .scoreAlias = mode { true } else { false }
                    await persistAirdropRegistration(airdrop: airdrop, usesScoreAlias: usesScoreAlias)
                case let .failure(failedExtrinsic):
                    throw failedExtrinsic.error
                }
            }
        } catch {
            logger.error(
                "[GameDebug] registerForGame FAILED airdrop=\(airdrop != nil ? "present" : "nil") error=\(error)"
            )
            throw error
        }
    }

    func resolveAirdropProof() async -> GamePallet.AirdropVrfs? {
        guard let gameInfo = await state.gameInfo else {
            logger.debug("[GameDebug] resolveAirdropProof: no gameInfo available -> nil")
            return nil
        }
        logger.debug(
            "[GameDebug] resolveAirdropProof: gameIndex=\(gameInfo.index) "
                + "airdropScheduled=\(gameInfo.airdropScheduled)"
        )
        do {
            let airdrop = try await dim2FlowState.airdropService.makeProof(for: gameInfo)
            logger.debug(
                "[GameDebug] resolveAirdropProof: resolved airdrop=\(airdrop != nil ? "present" : "nil")"
            )
            return airdrop
        } catch {
            logger.error("[GameDebug] resolveAirdropProof FAILED — registering without airdrop: \(error)")
            return nil
        }
    }

    func persistAirdropRegistration(airdrop: GamePallet.AirdropVrfs?, usesScoreAlias: Bool) async {
        guard let airdrop, let gameIndex = await state.gameInfo?.index else { return }
        do {
            let beneficiary = try walletRepo.depositWallet().getMultiSigner().getAccountId()
            try await airdropRegistrationStore.save(
                AirdropRegistrationRecord(
                    gameIndex: gameIndex,
                    beneficiary: beneficiary,
                    usesScoreAlias: usesScoreAlias
                )
            )
            let variant = if case .alias = airdrop { "Alias" } else { "Account" }
            logger.debug(
                "[GameDebug] airdrop registration persisted gameIndex=\(gameIndex) usesScoreAlias=\(usesScoreAlias) " +
                    "airdropVariant=\(variant) " +
                    "beneficiary=depositWallet(\(beneficiary.toHex(includePrefix: true).prefix(12))…)"
            )
        } catch {
            logger.error("[GameDebug] failed to persist airdrop registration: \(error)")
        }
    }

    func handlePostRegistrationSuccess() async {
        let gameInfo = await state.gameInfo
        let gameSchedule = await state.gameSchedule

        requestNotificationAuthorization(for: gameInfo, gameSchedule: gameSchedule)

        await sendRegistrationTelemetry()

        gameRegistrationSubject.send(gameInfo)

        await requestCalendarAccessAfterRegistration()
        await requestAlarmNotificationAuthorization()
        await localNetworkPermissionService.requestPermissionIfNeeded()
    }

    func sendRegistrationTelemetry() async {
        guard let telemetry = dim2FlowState.gameDashboardTelemetry else { return }

        do {
            let chain = try dim2FlowState.chainRegistry.getChainOrError(for: dim2FlowState.chainId)
            let wallet = try GameAccountFactory.makeWallet(for: dim2FlowState.source)
            let account = try wallet.fetchAccount(for: chain)

            guard let username = dim2FlowState.usernameStorage.username?.value else {
                logger.warning("Skipping dashboard registration telemetry — username unexpectedly nil")
                return
            }

            let usernameAccountId = try walletRepo.main().fetchAccount(for: chain).accountId

            telemetry.sendRegistration(
                localAccount: account.accountId,
                usernameAccountId: usernameAccountId,
                username: username
            )
        } catch {
            logger.warning("Skipping dashboard registration telemetry: \(error)")
        }
    }

    func requestNotificationAuthorization(for gameInfo: GameInfo?, gameSchedule: GameSchedule?) {
        logger.debug("Checking notification auth after registration")

        let localNotificationService = gameNotificationsService.localNotificationService
        localNotificationService.notificationAccessStatus { [weak self] status in
            guard !status.accessGranted else {
                self?.scheduleNotificationsAfterAuth(for: gameInfo, gameSchedule: gameSchedule)
                return
            }

            let enableNotifications = DIM2EnableNotifications { granted in
                guard granted else { return }

                self?.scheduleNotificationsAfterAuth(for: gameInfo, gameSchedule: gameSchedule)
            }

            self?.enableNotificationsSubject.send(enableNotifications)
        }
    }

    func scheduleNotificationsAfterAuth(for gameInfo: GameInfo?, gameSchedule: GameSchedule?) {
        gameNotificationsService.scheduleGameStartNotifications(for: gameInfo)

        logger.debug("Game start notification scheduled")

        gameNotificationsService.scheduleRegistrationStartNotifications(
            for: gameSchedule,
            currentGameInfo: gameInfo
        )

        gameNotificationsService.scheduleRegistrationOpenNotifications(for: gameSchedule)

        logger.debug("Registration start notification scheduled")
    }

    func requestAlarmNotificationAuthorization() async {
        if #available(iOS 26.1, *) {
            do {
                let result = try await AlarmManager.shared.requestAuthorization()
                guard result == .authorized else { return }
                await rescheduleGameAlarm()
            } catch {
                logger.error("Alarm authorization request failed: \(error)")
            }
        }
    }
}

// MARK: - Deposits

private extension DIM2ChatInteractor {
    func createDepositTask() -> Task<Void, Never> {
        Task { [weak self] in
            do {
                guard
                    let requiredBalanceOperationFactory = self?.requiredBalanceOperationFactory,
                    let dim2FlowState = self?.dim2FlowState,
                    let balanceTrackingFactory = self?.balanceTrackingFactory else {
                    return
                }

                self?.logger.debug("Will start deposit tracking")

                let requiredBalance = try await requiredBalanceOperationFactory
                    .flowRequiredBalanceWrapper()
                    .asyncExecute()

                let asset = try dim2FlowState.getDepositAsset()
                let accountId = try dim2FlowState.candidateWallet.getRawPublicKey()

                for try await actualBalance in balanceTrackingFactory.trackAccountAsset(
                    accountId,
                    chainAsset: asset
                ) {
                    await self?.state.updateBalance(
                        required: requiredBalance,
                        current: actualBalance.transferable
                    )

                    self?.logger.debug(
                        "Received new balance: \(actualBalance.transferable) deposit: \(requiredBalance)"
                    )
                }
            } catch {
                self?.logger.error("Deposit state fetch failed: \(error)")
            }
        }
    }
}
