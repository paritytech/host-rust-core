import Foundation
import Observation

public protocol GameWidgetViewModelProtocol: Observable, Hashable {
    var actionViewModels: [ChatMessageActionView.ViewModel] { get set }
    var stateViewModel: GameStateViewModel? { get set }
    var upgradeUsernameViewModel: UpgradeUsernameViewModel? { get set }
}

@Observable
public final class GameWidgetViewModel: GameWidgetViewModelProtocol {
    public var actionViewModels: [ChatMessageActionView.ViewModel]
    public var stateViewModel: GameStateViewModel?
    public var upgradeUsernameViewModel: UpgradeUsernameViewModel?

    public init(
        actionViewModels: [ChatMessageActionView.ViewModel],
        stateViewModel: GameStateViewModel?,
        upgradeUsernameViewModel: UpgradeUsernameViewModel?
    ) {
        self.actionViewModels = actionViewModels
        self.stateViewModel = stateViewModel
        self.upgradeUsernameViewModel = upgradeUsernameViewModel
    }

    public static func == (lhs: GameWidgetViewModel, rhs: GameWidgetViewModel) -> Bool {
        lhs.actionViewModels == rhs.actionViewModels &&
            lhs.stateViewModel == rhs.stateViewModel &&
            lhs.upgradeUsernameViewModel == rhs.upgradeUsernameViewModel
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(actionViewModels)
        hasher.combine(stateViewModel)
        hasher.combine(upgradeUsernameViewModel)
    }
}

@Observable
public final class GameStateViewModel: Hashable {
    public var state: State
    public var isLoading: Bool
    public var isMember: Bool
    public var isRegisterEnabled: Bool

    public var onRegister: () -> Void = {}

    let countdownFormatter: CountdownDateFormatting
    let gameDateFormatter: GameDateFormatting
    let timeToJoinGameFormatter: TimestampFormatting

    public init(
        state: State,
        isLoading: Bool = false,
        isMember: Bool = false,
        isRegisterEnabled: Bool = true,
        countdownFormatter: CountdownDateFormatting,
        gameDateFormatter: GameDateFormatting = GameDateFormatter(timeOnNewLine: true),
        timeToJoinGameFormatter: TimestampFormatting = DateComponentsFormatter.secondsMinutesAbbreviated
    ) {
        self.state = state
        self.isLoading = isLoading
        self.isMember = isMember
        self.isRegisterEnabled = isRegisterEnabled
        self.countdownFormatter = countdownFormatter
        self.gameDateFormatter = gameDateFormatter
        self.timeToJoinGameFormatter = timeToJoinGameFormatter
    }

    public static func == (lhs: GameStateViewModel, rhs: GameStateViewModel) -> Bool {
        lhs.state == rhs.state &&
            lhs.isLoading == rhs.isLoading &&
            lhs.isMember == rhs.isMember &&
            lhs.isRegisterEnabled == rhs.isRegisterEnabled
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(state)
        hasher.combine(isLoading)
        hasher.combine(isRegisterEnabled)
        hasher.combine(isMember)
    }

    public func timeRemaining(until targetDate: Date, from other: Date) -> String {
        let seconds = max(0, Int(targetDate.timeIntervalSince(other)))
        guard seconds > 0 else {
            return String(localized: .Game.gameInProgress)
        }
        let formattedString = timeToJoinGameFormatter.string(
            for: targetDate,
            now: other
        )
        return String(localized: .Game.gameInfoCountdown(time: formattedString))
    }

    public func timeRemainingString(until targetDate: Date, from other: Date) -> String {
        timeUntil(targetDate, from: other)
    }

    public func formattedDateString(from date: Date) -> String {
        gameDateFormatter.format(date: date)
    }

    public func isStarting(_ other: Date) -> Bool {
        if case let .registered(date) = state { return date.timeIntervalSince(other) <= 0 }
        return false
    }

    private func timeUntil(
        _ date: Date,
        from startDate: Date
    ) -> String {
        guard date > startDate else {
            return ""
        }
        let timeLeft = countdownFormatter.formatWithSinglePart(to: date)
        return String(localized: .Game.gameStartInFormat(timeLeft))
    }
}

public extension GameStateViewModel {
    enum State: Hashable {
        case register(gameDate: Date)
        case registered(gameDate: Date)
        case starting(gameDate: Date)
    }
}
