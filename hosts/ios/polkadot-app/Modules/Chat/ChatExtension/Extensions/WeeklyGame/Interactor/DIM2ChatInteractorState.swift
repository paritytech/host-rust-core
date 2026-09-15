import Foundation
import SubstrateSdk
import AsyncExtensions
import Individuality

actor DIM2ChatInteractorState {
    private let logger: LoggerProtocol

    // MARK: - Widget State Properties

    private var isLoading = false
    private var depositIsSufficient: Bool?

    // MARK: - Balance State

    private var requiredBalance: Balance?
    private var currentBalance: Balance?

    // MARK: - External Data State

    private(set) var gameInfo: GameInfo?
    private(set) var scoreInfo: ScoreInfo?
    private(set) var gameSchedule: GameSchedule?
    private var gameHistory: GameHistory?
    private var registeredData: People.RegisteredData?
    private var accountOrPerson: GamePallet.AccountOrPerson?
    private(set) var candidate: ProofOfInkPallet.Candidate?
    private(set) var flakeOutInProgress: Bool = false

    private var airdropRegisteringGameIndex: GamePallet.GameIndex?

    private var depositTrackingTask: Task<Void, Never>?

    init(logger: LoggerProtocol = Logger.shared) {
        self.logger = logger
    }

    // MARK: - State Change Callback

    private var onWidgetUpdate: ((DIM2WidgetState) -> Void)?
    private var onDepositTaskStart: (() -> Task<Void, Never>?)?

    // MARK: - State Updates

    func setOnWidgetUpdate(_ onWidgetUpdate: ((DIM2WidgetState?) -> Void)?) {
        self.onWidgetUpdate = onWidgetUpdate
    }

    func setOnDepositTaskStart(_ onDepositTaskStart: (() -> Task<Void, Never>?)?) {
        self.onDepositTaskStart = onDepositTaskStart
    }

    func updateGameInfo(_ newGameInfo: GameInfo?) {
        gameInfo = newGameInfo
        updateDepositTask()
        updateWidgetState()
    }

    func updateScoreInfo(_ newScoreInfo: ScoreInfo?) {
        scoreInfo = newScoreInfo
        updateWidgetState()
    }

    func updateGameSchedule(_ newGameSchedule: GameSchedule?) {
        gameSchedule = newGameSchedule
        updateWidgetState()
    }

    func updateGameHistory(_ newGameHistory: GameHistory?) {
        gameHistory = newGameHistory
        updateWidgetState()
    }

    func updateRegisteredData(_ newRegisteredData: People.RegisteredData?) {
        registeredData = newRegisteredData
        updateDepositTask()
        updateWidgetState()
    }

    func getAccountOrPerson() -> GamePallet.AccountOrPerson? {
        accountOrPerson
    }

    func updateAccountOrPerson(_ newAccountOrPerson: GamePallet.AccountOrPerson?) {
        guard accountOrPerson != newAccountOrPerson else {
            return
        }

        logger.debug("Updating account or person: \(String(describing: newAccountOrPerson))")
        accountOrPerson = newAccountOrPerson
    }

    func updateBalance(required: Balance?, current: Balance?) {
        requiredBalance = required
        currentBalance = current
        updateWidgetState()
    }

    func setLoading(_ loading: Bool) {
        isLoading = loading
        updateWidgetState()
    }

    func updateCandidate(_ newCandidate: ProofOfInkPallet.Candidate?) {
        candidate = newCandidate
        updateWidgetState()
    }

    func updateOffboard(inProgress: Bool) {
        flakeOutInProgress = inProgress
        updateWidgetState()
    }

    // MARK: - Computed State Helpers

    var shouldSkipBalanceCheck: Bool {
        gameInfo?.isCrediblePlayer == true
            || registeredData?.source.isNotGameRecognizedPerson == true
    }

    var canStartPlaying: Bool {
        guard let gameDate = gameInfo?.gameDate else { return false }
        return gameDate.timeIntervalSince(.now) <= .secondsInHour
    }

    var calendarEvent: CalendarGameModel? {
        guard
            let gameInfo,
            gameInfo.state == .registration,
            gameInfo.isRegistered,
            let gameDate = gameInfo.gameDate,
            gameDate.timeIntervalSince(.now) >= .secondsInHour
        else {
            return nil
        }

        return CalendarGameFactory.makeCalendarGame(for: gameInfo)
    }

    func makeRegisterMode() -> GameRegisterMode {
        if let registeredData, registeredData.source.isNotGameRecognizedPerson {
            return .scoreAlias(registeredData.scoreAlias.alias)
        }

        let isCrediblePlayer = gameInfo?.isCrediblePlayer == true
        return .player(isCredible: isCrediblePlayer)
    }

    var hasExternalCredibility: Bool {
        registeredData?.source.isNotGameRecognizedPerson == true
    }
}

// MARK: - Airdrop Registration Gate

extension DIM2ChatInteractorState {
    func airdropRegistrationGateGameIndex() -> GamePallet.GameIndex? {
        guard case .register = resolveGameState() else { return nil }
        guard gameInfo?.airdropScheduled == true, !currentAirdropRegistering else { return nil }
        return gameInfo?.index
    }

    func confirmAirdropRegistering(forGameIndex index: GamePallet.GameIndex) {
        guard airdropRegisteringGameIndex != index else { return }
        airdropRegisteringGameIndex = index
        updateWidgetState()
    }
}

// MARK: - Widget State Building

private extension DIM2ChatInteractorState {
    func updateWidgetState() {
        let state = buildWidgetState()
        onWidgetUpdate?(state)
    }

    func buildWidgetState() -> DIM2WidgetState {
        let gameState = resolveGameState()
        let personRegistrationState = resolvePersonRegistrationState()

        let gameRegistrationState = resolveGameRegistrationState(gameState: gameState)

        return DIM2WidgetState(
            gameState: gameState,
            isLoading: isLoading,
            personRegistrationState: personRegistrationState,
            gameRegistrationState: gameRegistrationState,
            switchToDIM1: switchToDIM1State()
        )
    }

    var currentAirdropRegistering: Bool {
        guard let index = gameInfo?.index else { return false }
        return airdropRegisteringGameIndex == index
    }

    func resolveGameState() -> DIM2WidgetState.GameState? {
        guard gameInfo?.isReportSent != true else {
            return nil
        }

        let isRegistered = gameInfo?.isRegistered == true

        switch gameInfo?.state {
        case .registration where isRegistered,
             .shuffle where isRegistered,
             .inProgress where isRegistered:
            guard let date = gameInfo?.gameDate else { return nil }
            return canStartPlaying ? .starting(gameDate: date) : .registered(gameDate: date)

        case .registration:
            guard let date = gameInfo?.gameDate else { return nil }
            return .register(gameDate: date)

        case .shuffle,
             .inProgress,
             .processing,
             .cancelling,
             nil:
            return nil
        }
    }

    func resolvePersonRegistrationState() -> DIM2WidgetState.PersonRegistrationState {
        guard let registeredData, registeredData.source.isGameRecognizedPerson else {
            return .notGamePerson
        }

        if registeredData.isUsernameUpgradeAvailable {
            return .needsFullUsername(registeredData)
        } else {
            return .gamePerson
        }
    }

    func resolveGameRegistrationState(
        gameState: DIM2WidgetState.GameState?
    ) -> DIM2WidgetState.GameRegistrationState {
        // Registration isn't open yet: the register phase is showing for a game with a scheduled
        // airdrop that hasn't reached the Registering phase. Surfaced as "Opening soon" (inactive).
        if case .register = gameState, gameInfo?.airdropScheduled == true, !currentAirdropRegistering {
            return .openingSoon
        }

        guard let gameInfo else {
            return .unknown
        }

        guard !gameInfo.isCrediblePlayer else {
            return .canRegister
        }

        // If can become or is a polkadot peer and originating from DIM1
        if let registeredData, registeredData.source.isNotGameRecognizedPerson {
            return .canRegister
        }

        guard let currentBalance, let requiredBalance else {
            return .unknown
        }

        if currentBalance >= requiredBalance {
            return .canRegister
        } else {
            return .requiresDeposit(.init(requiredAmount: requiredBalance, currentBalance: currentBalance))
        }
    }

    func updateDepositTask() {
        if shouldSkipBalanceCheck {
            depositTrackingTask?.cancel()
            depositTrackingTask = nil
        } else {
            guard depositTrackingTask == nil else {
                return
            }

            depositTrackingTask = onDepositTaskStart?()
        }
    }
}

// MARK: - DIM1 State Handling

private extension DIM2ChatInteractorState {
    enum DIM1StateResolution {
        case notApplied
        case candidate(flakeOutAvailable: Bool)
    }

    func resolveDIM1State() -> DIM1StateResolution {
        guard let candidate else {
            return .notApplied
        }

        switch candidate {
        case .applied:
            return .candidate(flakeOutAvailable: true)
        case .selected:
            return .candidate(flakeOutAvailable: false)
        case .proven:
            return .candidate(flakeOutAvailable: false)
        }
    }

    func switchToDIM1State() -> DIM2WidgetState.SwitchToDIM1State? {
        switch resolveDIM1State() {
        case .notApplied:
            nil
        case let .candidate(flakeOutAvailable):
            .init(possible: flakeOutAvailable, inProgress: flakeOutInProgress)
        }
    }
}
