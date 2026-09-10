import Foundation

protocol GameHistoryMaking {
    func makeGameHistory(syncData: GameHistorySyncData) -> GameHistory?
}

final class GameHistoryFactory {
    private let logger: LoggerProtocol

    init(logger: LoggerProtocol = Logger.shared) {
        self.logger = logger
    }
}

extension GameHistoryFactory: GameHistoryMaking {
    func makeGameHistory(syncData: GameHistorySyncData) -> GameHistory? {
        guard
            let actualGameDates = syncData.actualGameDates,
            let range = syncData.range
        else {
            return nil
        }

        let attendanceHistory = syncData.attendanceHistory ?? []
        let activeGameIndex = syncData.game?.index
        let isReportSent = syncData.player?.sentReport == true

        logger.debug("Actual game dates: \(actualGameDates)")

        return GameHistory(
            items: range.compactMap { index in
                guard let date = actualGameDates[index] else {
                    logger.debug("Missing actual game date for index: \(index)")
                    return nil
                }

                if index == activeGameIndex {
                    return .init(
                        status: isReportSent ? .waitingForResult : .pending,
                        date: date,
                        index: index
                    )
                }

                return .init(
                    status: attendanceHistory.contains(index) ? .success : .failure,
                    date: date,
                    index: index
                )
            },
            blockHash: syncData.blockHash
        )
    }
}
