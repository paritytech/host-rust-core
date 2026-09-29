import Foundation

protocol GameReportViewModelProviding {
    func provideViewModel(
        votes: [GameVote],
        confirmButtonState: GameReportViewLayout.ConfirmButtonState,
        isGameEnded: Bool,
        gameDate: Date?
    ) -> GameReportViewLayout.ViewModel
}

final class GameReportViewModelProvider: GameReportViewModelProviding {
    let locale: Locale

    init(locale: Locale = .current) {
        self.locale = locale
    }

    func provideViewModel(
        votes: [GameVote],
        confirmButtonState: GameReportViewLayout.ConfirmButtonState,
        isGameEnded: Bool,
        gameDate: Date?
    ) -> GameReportViewLayout.ViewModel {
        if isGameEnded {
            return .ended(gameTitle: endedTitle(for: gameDate))
        }

        return .reporting(votes: votes.filter { !$0.isBanned }, confirmButtonState: confirmButtonState)
    }
}

private extension GameReportViewModelProvider {
    func endedTitle(for date: Date?) -> String {
        let dateString: String

        if let date {
            let formatter = DateFormatter.fullMonthDay.value(for: locale)
            dateString = formatter.string(from: date)
        } else {
            dateString = ""
        }

        return String(localized: .Game.gameReportEndedTitle(dateString))
    }
}
