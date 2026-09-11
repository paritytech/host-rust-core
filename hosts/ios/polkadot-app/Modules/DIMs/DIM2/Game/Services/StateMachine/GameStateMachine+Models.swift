import Foundation
import SubstrateSdk
import Individuality

extension GameStateMachine {
    enum State: Equatable {
        case preparing(PreparingInfo)
        case round(Round, RoundsInfo)
        case finished(FinishedInfo)

        var gameplayRound: Round? {
            guard
                case let .round(round, _) = self,
                case let .hosting(hosting) = round.state,
                case .gameplay = hosting.state
            else {
                return nil
            }

            return round
        }

        var isGameplay: Bool {
            gameplayRound != nil
        }

        var gameplayRoundIndex: Int? {
            gameplayRound?.roundIndex
        }

        var isFinished: Bool {
            if case .finished = self {
                return true
            }
            return false
        }
    }

    struct PreparingInfo: Equatable {
        let gameDate: Date?
        let subroundsCount: Int?
        let preconnectPlayers: [AccountId]?
        let preconnectGameIndex: GamePallet.GameIndex?

        static func == (_: PreparingInfo, _: PreparingInfo) -> Bool {
            false
        }
    }

    struct Round: Equatable {
        let players: [AccountId]
        let preconnectPlayers: [AccountId]?
        let state: RoundState
        let roundIndex: Int

        static func == (lhs: Round, rhs: Round) -> Bool {
            lhs.state == rhs.state
                && lhs.roundIndex == rhs.roundIndex
        }
    }

    enum RoundState: Equatable {
        case hosting(Hosting)
    }

    struct Hosting: Equatable {
        let host: AccountId
        let state: HostingState
        let hostIndex: Int

        static func == (lhs: Hosting, rhs: Hosting) -> Bool {
            lhs.state == rhs.state
                && lhs.hostIndex == rhs.hostIndex
        }
    }

    enum HostingState: Equatable {
        case transition(left: TimeInterval, total: TimeInterval)
        case introduction
        case gameplay(left: TimeInterval, total: TimeInterval)
        case end

        static func == (lhs: HostingState, rhs: HostingState) -> Bool {
            switch (lhs, rhs) {
            case let (.transition(lhsLeft, _), .transition(rhsLeft, _)),
                 let (.gameplay(lhsLeft, _), .gameplay(rhsLeft, _)):
                lhsLeft == rhsLeft
            case (.introduction, .introduction),
                 (.end, .end):
                true
            default:
                false
            }
        }
    }

    struct RoundsInfo: Equatable {
        let gameIndex: GamePallet.GameIndex
        let gameDate: Date
        let subroundsCount: Int
        let subroundIndex: Int
    }

    struct FinishedInfo: Equatable {
        let gameIndex: GamePallet.GameIndex
        let subroundsCount: Int
    }
}

extension GameStateMachine {
    struct GameInProgressInput {
        let gameDate: Date
        let gameIndex: GamePallet.GameIndex
        let isReportSent: Bool
    }

    struct RoundStateInput {
        let diff: Double
        let start: Double
        let duration: Double
        let index: Int
        let gameIndex: GamePallet.GameIndex
        let gameDate: Date
        let subroundsCount: Int
    }

    enum TimeIntervals {
        static let preconnect = TimeInterval(10)
        static let hostIntroduction = TimeInterval(2)
        static let hostingEnd = TimeInterval(2)
        static let hostingGameplayMinimumDuration = TimeInterval(8)
        static let hostingGameplayDelay = hostIntroduction
        static let hostingGameplayOffset = hostingGameplayDelay + hostingEnd
        static let hostingMinimumDuration = hostingGameplayOffset + hostingGameplayMinimumDuration
    }
}
