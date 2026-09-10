import UIKit
import SubstrateSdk
import Keystore_iOS

// @unchecked Sendable: all mutable state confined to serial workQueue
final class GameVideoInteractor: @unchecked Sendable {
    weak var presenter: GameVideoInteractorOutputProtocol?

    let accountId: AccountId

    private var voting: GameVideoVoting
    private let gameVideoService: GameVideoServicing
    private let gameVoteService: GameVoteServicing
    private let bannedPlayerService: BannedPlayerServicing
    private let gameStartReminder: any GameStartReminderServicing
    private let application: UIApplication
    private let settingsManager: SettingsManagerProtocol
    private let workQueue: DispatchQueue
    private let logger: LoggerProtocol

    private let infoSyncService: GameInfoSyncServicing
    private let intendedGameId: Game.Identifier?

    private var gameId: Game.Identifier?
    private var rtcIceConnectedFlags = [AccountId: Bool]()
    private var gestureAcceptances = Set<AccountId>()
    private var bannedPlayers = Set<AccountId>()
    private var playersWithPreview = Set<AccountId>()
    private var lastTrackedHost: AccountId?
    private var alarmCancelationTask: Task<Void, Error>?
    private var intendedGameCheckTask: Task<Void, Error>?
    private var isGameThrottled = false

    init(
        accountId: AccountId,
        gameVideoService: GameVideoServicing,
        infoSyncService: GameInfoSyncServicing,
        intendedGameId: Game.Identifier? = nil,
        gameVoteService: GameVoteServicing = GameVoteService(),
        bannedPlayerService: BannedPlayerServicing = BannedPlayerService(),
        gameStartReminder: any GameStartReminderServicing,
        application: UIApplication,
        settingsManager: SettingsManagerProtocol,
        workQueue: DispatchQueue,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.accountId = accountId
        voting = .init(accountId: accountId)
        self.gameVideoService = gameVideoService
        self.infoSyncService = infoSyncService
        self.intendedGameId = intendedGameId
        self.gameVoteService = gameVoteService
        self.bannedPlayerService = bannedPlayerService
        self.gameStartReminder = gameStartReminder
        self.application = application
        self.settingsManager = settingsManager
        self.workQueue = workQueue
        self.logger = logger
    }

    deinit {
        logger.debug("GameVideoInteractor.deinit")
        alarmCancelationTask?.cancel()
        intendedGameCheckTask?.cancel()
        throttleGameResources(isGameFinished: false)
    }
}

extension GameVideoInteractor: GameVideoInteractorInputProtocol {
    func setup() {
        gameVideoService.setup()
        provideTutorialTooltipState()
        provideSwipeTooltipState()
        subscribeToCheckIntendedGame()
        scheduleCancellationCheckIfNeeded()
        loadBannedPlayers()
    }

    func throttle(isGameFinished: Bool) {
        throttleGameResources(isGameFinished: isGameFinished)
    }

    func performVotingAction(for player: AccountId, vote: GameVideoVotingState?) {
        workQueue.async { [logger, weak self] in
            guard let self else {
                return
            }

            guard let vote else {
                // if there is no vote, just mark player as interacted with
                voting.interactWithPlayer(player)
                provideVoting()
                return
            }

            logger.debug("Performing vote for player: \(player.toHex().prefix(8)), vote: \(vote)")

            guard shouldCountVote(for: player) else {
                logger.warning("Vote skipped shouldn't count vote")
                return
            }

            guard voting.vote(for: player, vote: vote) else {
                logger.warning("Voting failed, state: \(voting)")
                return
            }
            logger.debug("Successful vote")

            gameVideoService.sendGestureAcceptance(for: player, vote: vote)
            switch vote {
            case .positive,
                 .negative:
                savePreview(for: player)
            case .notDecided:
                break
            }
            provideVoting()
        }
    }

    func banPlayer(_ player: AccountId) {
        Task {
            try await bannedPlayerService.save(player)
            ban(player: player)
        }
    }

    func unbanPlayer(_ player: AccountId) {
        Task {
            try await bannedPlayerService.delete(player)
            unban(player: player)
        }
    }

    func setTutorialTooltip(shown: Bool) {
        settingsManager.set(value: shown, for: .playerTooltipShown)
        provideTutorialTooltipState()
    }

    func setSwipeTooltip(shown: Bool) {
        settingsManager.set(value: shown, for: .swipeTooltipShown)
        provideSwipeTooltipState()
    }
}

extension GameVideoInteractor: GameVideoServiceDelegate {
    func gameVideoService(
        _: any GameVideoServicing,
        didUpdateState state: GameStateMachine.State?,
        isPlayersChanged: Bool
    ) {
        logger.debug("Did update state to \(String(describing: state)), isPlayersChanged = \(isPlayersChanged)")

        dispatchPrecondition(condition: .onQueue(workQueue))

        handleState(state)
        provideState(state, isPlayersChanged: isPlayersChanged)
    }

    func gameVideoService(
        _: any GameVideoServicing,
        didUpdateRTCIceConnectedFlags flags: [AccountId: Bool]
    ) {
        logger.debug("Did update RTC ice connected flags")

        dispatchPrecondition(condition: .onQueue(workQueue))

        rtcIceConnectedFlags = flags
        provideRTCIceConnectedFlags(flags)
    }

    func gameVideoService(
        _: any GameVideoServicing,
        didReceiveGestureAcceptance message: Game.DataChannelMessage.GestureAcceptanceMessage
    ) {
        dispatchPrecondition(condition: .onQueue(workQueue))

        let didChange: Bool =
            switch message.state {
            case .accept:
                gestureAcceptances.insert(message.acceptorAccountId).inserted
            case .unnaccept:
                gestureAcceptances.remove(message.acceptorAccountId) != nil
            }

        guard didChange else {
            return
        }

        provideGestureAcceptances()
    }
}

private extension GameVideoInteractor {
    func throttleGameResources(isGameFinished: Bool) {
        guard !isGameThrottled else {
            logger.debug("Already throttled")
            return
        }

        isGameThrottled = true
        logger.debug("Throttling game resources")
        gameVideoService.throttle(isGameFinished: isGameFinished)
    }

    func handleState(_ state: GameStateMachine.State?) {
        updateGameId(from: state)
        clearGestureAcceptancesIfNeeded(from: state)

        switch state {
        case let .round(round, _):
            handleRound(round)
        case .finished:
            finalizePendingVotes()
        case .preparing,
             nil:
            break
        }
    }

    func clearGestureAcceptancesIfNeeded(from state: GameStateMachine.State?) {
        guard !(state?.isGameplay ?? false) else {
            return
        }

        clearGestureAcceptances()
    }

    func updateGameId(from state: GameStateMachine.State?) {
        guard gameId == nil else {
            return
        }
        switch state {
        case let .round(_, roundsInfo):
            gameId = .init(index: roundsInfo.gameIndex)
        case let .finished(finishedInfo):
            gameId = .init(index: finishedInfo.gameIndex)
        case .preparing,
             nil:
            break
        }
        provideGameId(gameId: gameId)
    }

    func handleRound(_ round: GameStateMachine.Round) {
        switch round.state {
        case let .hosting(hosting):
            handleHosting(hosting, players: round.players)
        }
    }

    func handleHosting(_ hosting: GameStateMachine.Hosting, players: [AccountId]) {
        switch hosting.state {
        case .transition,
             .introduction:
            finalizePendingVotesIfHostChanged(to: hosting.host)
            prepareVoting(for: hosting.host, players: players)
        case let .gameplay(left, total):
            finalizePendingVotesIfHostChanged(to: hosting.host)
            prepareVoting(for: hosting.host, players: players)
            ensurePlayersHavePreview(
                players,
                gameplayLeft: left,
                gameplayTotal: total
            )
        case .end:
            logger.debug("Voting state before host ending: \(voting)")
            let isHostDisconnected = rtcIceConnectedFlags[hosting.host] != true
            voting.applyAutoRejection(isHostDisconnected: isHostDisconnected)
            provideVoting()
            // Save deferred so the user can still revert any auto-applied vote during the .end window.
            // Persisted on next host start or game end.
        }
    }

    func finalizePendingVotesIfHostChanged(to newHost: AccountId) {
        defer {
            lastTrackedHost = newHost
        }
        guard let lastTrackedHost, lastTrackedHost != newHost else {
            return
        }
        saveGameVotes()
    }

    func finalizePendingVotes() {
        guard lastTrackedHost != nil else {
            return
        }
        saveGameVotes()
        lastTrackedHost = nil
    }

    func unban(player: AccountId) {
        workQueue.async { [weak self] in
            guard let self else { return }
            bannedPlayers.remove(player)
            provideBannedPlayers()
        }
    }

    func ban(player: AccountId) {
        workQueue.async { [weak self] in
            guard let self else { return }
            bannedPlayers.insert(player)
            provideBannedPlayers()
        }
    }

    func saveGameVotes() {
        guard let gameIndex = gameId?.index else {
            return
        }

        // Capture data safely on workQueue before entering async context
        let statesByPlayer = voting.statesByPlayer
        let bannedPlayers = bannedPlayers

        Task { [gameVoteService, logger] in
            for (accountId, votingState) in statesByPlayer {
                do {
                    let delta =
                        switch votingState {
                        case .positive: 1
                        case .negative: -1
                        case .notDecided: 0
                        }

                    try await gameVoteService.updateVoteCounter(
                        votesToAdd: delta,
                        for: accountId,
                        gameIndex: gameIndex,
                        isBanned: bannedPlayers.contains(accountId)
                    )
                } catch {
                    logger.error("Failed to update vote counter: \(error)")
                }
            }
        }
    }

    func provideGameId(gameId: Game.Identifier?) {
        DispatchQueue.main.async { [weak self] in
            self?.presenter?.didReceive(
                gameId: gameId
            )
        }
    }

    func subscribeToCheckIntendedGame() {
        guard let intendedGameId else { return }

        intendedGameCheckTask = Task { [weak self, infoSyncService, intendedGameId] in
            for try await gameInfo in infoSyncService.observe() {
                guard let gameInfo else { continue }

                let isCurrent = gameInfo.index == intendedGameId.index
                if !isCurrent {
                    await MainActor.run { [weak self] in
                        self?.presenter?.didReceiveIntendedGameEnded(intendedGameId: intendedGameId)
                        self?.intendedGameCheckTask?.cancel()
                    }
                }
                return
            }
        }
    }

    func provideState(_ state: GameStateMachine.State?, isPlayersChanged: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.presenter?.didReceive(
                state: state,
                isPlayersChanged: isPlayersChanged
            )
        }
    }

    func provideRTCIceConnectedFlags(_ flags: [AccountId: Bool]) {
        DispatchQueue.main.async { [weak self] in
            self?.presenter?.didReceive(
                rtcIceConnectedFlags: flags
            )
        }
    }

    func provideVoting() {
        DispatchQueue.main.async { [weak self, voting] in
            self?.presenter?.didReceive(
                voting: voting
            )
        }
    }

    func provideGestureAcceptances() {
        DispatchQueue.main.async { [weak self, gestureAcceptances] in
            self?.presenter?.didReceive(
                gestureAcceptances: gestureAcceptances
            )
        }
    }

    func provideBannedPlayers() {
        DispatchQueue.main.async { [weak self, bannedPlayers] in
            self?.presenter?.didReceive(
                bannedPlayers: bannedPlayers
            )
        }
    }

    func clearGestureAcceptances() {
        guard !gestureAcceptances.isEmpty else {
            return
        }

        gestureAcceptances.removeAll()
        provideGestureAcceptances()
    }

    func savePreview(for player: AccountId) {
        DispatchQueue.main.async { [weak self] in
            let image = self?.presenter?.requestPreview(for: player)
            self?.updatePreviewImage(image, for: player)
        }
    }

    func updatePreviewImage(_ image: UIImage?, for player: AccountId) {
        workQueue.async { [weak self] in
            guard
                let image,
                let self,
                let gameIndex = gameId?.index
            else {
                return
            }
            playersWithPreview.insert(player)

            Task { [weak self] in
                do {
                    try await self?.gameVoteService.updatePreviewImage(
                        image,
                        for: player,
                        gameIndex: gameIndex
                    )
                } catch {
                    self?.logger.error("Failed to update preview image: \(error)")
                }
            }
        }
    }

    func prepareVoting(for host: AccountId, players: [AccountId]) {
        if voting.prepareVoting(for: host, players: players) {
            provideVoting()
        }
    }

    func ensurePlayersHavePreview(
        _ players: [AccountId],
        gameplayLeft: TimeInterval,
        gameplayTotal: TimeInterval
    ) {
        let gameplayMiddle = gameplayTotal / 2

        guard gameplayLeft < gameplayMiddle else {
            return
        }

        for player in players {
            guard
                !playersWithPreview.contains(player),
                shouldCountVote(for: player),
                voting.canVote(for: player)
            else {
                continue
            }
            savePreview(for: player)
        }
    }

    func shouldCountVote(for player: AccountId) -> Bool {
        rtcIceConnectedFlags[player] == true
            && !bannedPlayers.contains(player)
    }

    func scheduleCancellationCheckIfNeeded() {
        let fireDateInt: Int? =
            if #available(iOS 26.1, *) {
                settingsManager.integer(for: .gameAlarmFireDate)
            } else {
                settingsManager.integer(for: .gameStartNotificationDate)
            }

        guard let fireDateInt else { return }

        let fireDate = Date(timeIntervalSinceReferenceDate: TimeInterval(fireDateInt))
        let delay = fireDate.timeIntervalSince(.now)

        // perform check just before alarm / notification  fires
        let checkDelay = delay - 1
        guard checkDelay > 0 else { return }

        alarmCancelationTask = Task { [weak self] in
            try await Task.sleep(for: .seconds(checkDelay))
            await MainActor.run { [weak self] in
                guard let self,
                      application.applicationState == .active,
                      presenter != nil else {
                    return
                }
                gameStartReminder.cancelReminder()
            }
        }
    }

    func provideTutorialTooltipState() {
        let playerTooltipShown = settingsManager.value(for: .playerTooltipShown)
        MainActor.assumeIsolated {
            presenter?.didReceive(playerTooltipShown: playerTooltipShown)
        }
    }

    func provideSwipeTooltipState() {
        let swipeTooltipShown = settingsManager.value(for: .swipeTooltipShown)
        MainActor.assumeIsolated {
            presenter?.didReceive(swipeTooltipShown: swipeTooltipShown)
        }
    }

    func loadBannedPlayers() {
        Task { [weak self, bannedPlayerService] in
            guard let loaded = try? await bannedPlayerService.fetchAll() else { return }
            self?.workQueue.async { [weak self] in
                self?.bannedPlayers = loaded
                self?.provideBannedPlayers()
            }
        }
    }
}
