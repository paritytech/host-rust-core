import Foundation
import AsyncExtensions
import SubstrateSdk
import PolkadotUI
import Individuality

// MARK: - Widget State (Pure Data)

struct DIM2WidgetState: Equatable {
    enum GameState: Hashable {
        case register(gameDate: Date)
        case registered(gameDate: Date)
        case starting(gameDate: Date)
    }

    struct DepositInfo: Hashable {
        let requiredAmount: Balance
        let currentBalance: Balance

        var neededAmount: Balance {
            requiredAmount.subtractOrZero(currentBalance)
        }
    }

    enum GameRegistrationState: Hashable {
        case unknown
        /// Registration is not open yet — the game's airdrop hasn't reached the Registering phase.
        /// The register button is shown but inactive ("Opening soon").
        case openingSoon
        case requiresDeposit(DepositInfo)
        case canRegister
    }

    enum PersonRegistrationState: Hashable {
        case notGamePerson
        case needsFullUsername(People.RegisteredData)
        case gamePerson
    }

    struct SwitchToDIM1State: Equatable {
        let possible: Bool
        let inProgress: Bool
    }

    let gameState: GameState?
    let isLoading: Bool
    let personRegistrationState: PersonRegistrationState
    let gameRegistrationState: GameRegistrationState
    let switchToDIM1: SwitchToDIM1State?
}

struct DIM2EnableNotifications {
    let callback: (Bool) -> Void
}

enum DIM2RegistrationError {
    case invitationServiceUnavailable(underlying: Error)
}

enum DIM2RegistrationDecision {
    case skipInvitation
    case cancel
}

typealias DIM2RegistrationDecisionHandler = (DIM2RegistrationError) async -> DIM2RegistrationDecision

protocol DIM2ChatInteracting: AnyObject {
    var dim2FlowState: DIM2SharedFlowStateProtocol { get }

    var logger: LoggerProtocol { get }

    /// Initialize internal observation tasks
    func setup() async

    /// Stream of widget state updates for footer configuration
    func observeWidgetState() -> AnyAsyncSequence<DIM2WidgetState>

    /// Stream of game registration events for message posting
    func observeGameRegistration() -> AnyAsyncSequence<GameInfo>

    /// Stream of game history for result messages
    func observeGameHistory() -> AnyAsyncSequence<GameHistory?>

    /// Stream of full username claimed events
    func observeFullUsernameClaimed() -> AnyAsyncSequence<FullUsernameClaimedMessageDecoder.Content>

    /// Stream of personhood registration events
    func observePersonhoodRegistered() -> AnyAsyncSequence<PeoplePallet.PersonalId>

    // Stream to observe when there is a need to present enable notification flow
    func observeEnableNotifications() -> AnyAsyncSequence<DIM2EnableNotifications>

    // ─────────────────────────────────────────────────────────────────────
    // QUERY
    // ─────────────────────────────────────────────────────────────────────

    func getScoreInfo() async -> ScoreInfo?
    func getGameInfo() async -> GameInfo?
    func fetchRemainingGamesResult(atBlock block: Data?) async throws -> RemainingGamesResult?
    func hasVotes(forGame index: UInt32) async throws -> Bool

    // ─────────────────────────────────────────────────────────────────────
    // MUTATION
    // ─────────────────────────────────────────────────────────────────────

    func register(decisionHandler: @escaping DIM2RegistrationDecisionHandler) async throws

    func switchToCurrentDim() async throws

    func rescheduleGameAlarm() async
}

extension DIM2ChatInteracting {
    func observeGameResults() -> AnyAsyncSequence<[GameResultsMessageDecoder.GameResult]> {
        observeGameHistory()
            .map { [weak self] history in
                do {
                    guard
                        let self,
                        let history,
                        !history.items.isEmpty,
                        let remainingResult = try await fetchRemainingGamesResult(
                            atBlock: history.blockHash
                        )
                    else {
                        return []
                    }

                    logger.debug("Remaining result: \(remainingResult)")

                    let index = history.items.lastNonPendingItem()?.index
                    var games: [GameResultsMessageDecoder.GameResult] = []

                    for game in history.items {
                        guard let state = game.gameResultState else {
                            continue
                        }

                        let hasVotes = await (try? hasVotes(forGame: game.index)) ?? false
                        let isCurrentGame = game.index == index

                        let gameResult = GameResultsMessageDecoder.GameResult(
                            index: game.index,
                            gameDate: game.date,
                            gamesLeft: remainingResult.gamesLeft,
                            state: state,
                            personhoodState: isCurrentGame
                                ? remainingResult.personhoodState
                                : .unknown,
                            hasVotes: hasVotes
                        )

                        games.append(gameResult)
                    }

                    return games
                } catch {
                    self?.logger.error("Error: \(error)")
                    return []
                }
            }
            .eraseToAnyAsyncSequence()
    }
}

private extension [GameHistory.Item] {
    func lastNonPendingItem() -> GameHistory.Item? {
        sorted {
            $0.index < $1.index
        }
        .last {
            switch $0.gameResultState {
            case .failure,
                 .success:
                true
            case .pending,
                 nil:
                false
            }
        }
    }
}

private extension GameHistory.Item {
    var gameResultState: GameResultsMessageDecoder.GameResult.State? {
        switch status {
        case .failure:
            .failure
        case .success:
            .success
        case .waitingForResult:
            .pending
        case .pending:
            nil
        }
    }
}
