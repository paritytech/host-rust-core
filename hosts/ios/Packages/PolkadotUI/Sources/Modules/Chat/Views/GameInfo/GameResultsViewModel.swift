import Foundation
import Observation

public enum GameResultStatus: Hashable {
    case pending
    case success
    case failed
}

public enum GamePersonhoodProgress: Hashable {
    case playing(gamesLeft: Int, suspended: Bool)
    case externallyRecognized
    case reachedPersonhood
    case unknown
}

public protocol GameResultsViewModelProtocol: Observable, Hashable {
    var gameDate: Date { get }
    var status: GameResultStatus { get }
    var personhoodProgress: GamePersonhoodProgress { get }
    var isLoading: Bool { get }
    var shouldShowAction: Bool { get }
    func formattedDateString() -> String
    func statusMessage() -> String
    func additionalMessage() -> String?
    func loadAvatars() async -> [AvatarViewModel]

    var onAction: () -> Void { get set }
}

@Observable
public final class GameResultsViewModel: GameResultsViewModelProtocol {
    public var gameDate: Date
    public let status: GameResultStatus
    public let personhoodProgress: GamePersonhoodProgress
    public var isLoading: Bool
    public var shouldShowAction: Bool

    public var onAction: () -> Void = {}

    private let avatarProvider: (() async -> [AvatarViewModel])?
    let gameDateFormatter: GameDateFormatting

    public init(
        gameDate: Date,
        status: GameResultStatus,
        personhoodProgress: GamePersonhoodProgress = .unknown,
        isLoading: Bool = false,
        shouldShowAction: Bool,
        avatarProvider: (() async -> [AvatarViewModel])? = nil,
        gameDateFormatter: GameDateFormatting = GameDateFormatter()
    ) {
        self.gameDate = gameDate
        self.status = status
        self.personhoodProgress = personhoodProgress
        self.isLoading = isLoading
        self.shouldShowAction = shouldShowAction
        self.avatarProvider = avatarProvider
        self.gameDateFormatter = gameDateFormatter
    }

    public static func == (lhs: GameResultsViewModel, rhs: GameResultsViewModel) -> Bool {
        lhs.gameDate == rhs.gameDate &&
            lhs.status == rhs.status &&
            lhs.personhoodProgress == rhs.personhoodProgress &&
            lhs.isLoading == rhs.isLoading &&
            lhs.shouldShowAction == rhs.shouldShowAction
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(gameDate)
        hasher.combine(status)
        hasher.combine(personhoodProgress)
        hasher.combine(isLoading)
        hasher.combine(shouldShowAction)
    }

    public func formattedDateString() -> String {
        gameDateFormatter.format(date: gameDate)
    }

    public func loadAvatars() async -> [AvatarViewModel] {
        guard shouldShowAction else { return [] }
        guard let avatarProvider else { return [] }
        return await avatarProvider()
    }

    public func statusMessage() -> String {
        switch (status, personhoodProgress) {
        case (.success, _):
            String(localized: .Game.resultStatusSuccess)
        case (.failed, .playing(_, suspended: true)):
            String(localized: .Game.resultStatusSuspended)
        case (.failed, _):
            String(localized: .Game.resultStatusFailed)
        case (.pending, _):
            String(localized: .Game.resultStatusPending)
        }
    }

    public func additionalMessage() -> String? {
        switch (status, personhoodProgress) {
        // Success cases
        case (.success, .playing(let gamesLeft, suspended: false)):
            String(localized: .Game.resultStatusMessagePlayToJoin(games: gamesLeft))
        case (.success, .playing(let gamesLeft, suspended: true)):
            String(localized: .Game.resultStatusMessagePlayToResume(games: gamesLeft))
        case (.success, .externallyRecognized):
            nil
        case (.success, .reachedPersonhood):
            String(localized: .Game.resultStatusMessageSecuredStatus)
        case (.success, .unknown):
            nil
        // Failed cases
        case (.failed, .playing(let gamesLeft, suspended: false)):
            String(localized: .Game.resultStatusMessagePlayToJoinFailed(games: gamesLeft))
        case (.failed, .playing(let gamesLeft, suspended: true)):
            String(localized: .Game.resultStatusMessagePlayToResumeFailed(games: gamesLeft))
        case (.failed, .externallyRecognized):
            String(localized: .Game.resultStatusMessageNoReward)
        case (.failed, .reachedPersonhood):
            String(localized: .Game.resultStatusMessageGameEnded)
        case (.failed, .unknown):
            String(localized: .Game.resultStatusMessageGameEnded)
        case (.pending, _):
            String(localized: .Game.resultStatusMessageProcessing)
        }
    }
}
