import UIKit
import SubstrateSdk
import PolkadotUI

protocol GameVideoViewModelMaking {
    func makeViewModel(
        input: GameVideoViewModelFactory.Input
    ) -> GameVideoViewLayout.ViewModel
}

final class GameVideoViewModelFactory {
    private let accountId: AccountId
    private let countdownDateFormatter: CountdownDateFormatting

    init(
        accountId: AccountId,
        countdownDateFormatter: CountdownDateFormatting = CountdownDateFormatter()
    ) {
        self.accountId = accountId
        self.countdownDateFormatter = countdownDateFormatter
    }
}

extension GameVideoViewModelFactory: GameVideoViewModelMaking {
    struct Input {
        let state: GameStateMachine.State?
        let rtcIceConnectedFlags: [AccountId: Bool]
        let voting: GameVideoVoting?
        let gestureAcceptances: Set<AccountId>
        let bannedPlayers: Set<AccountId>
        let isPlayersChanged: Bool
        let isPlayerTooltipShown: Bool
        let isSwipeTooltipShown: Bool
    }

    func makeViewModel(input: Input) -> GameVideoViewLayout.ViewModel {
        guard let state = input.state else {
            return makeDefaultViewModel(
                isPlayersChanged: input.isPlayersChanged
            )
        }

        switch state {
        case let .preparing(info):
            return makePreparingViewModel(
                input: input,
                info: info
            )
        case let .round(round, roundsInfo):
            return makeRoundViewModel(
                input: input,
                round: round,
                roundsInfo: roundsInfo
            )
        case .finished:
            return makeDefaultViewModel(isPlayersChanged: input.isPlayersChanged)
        }
    }
}

private extension GameVideoViewModelFactory {
    func makeDefaultViewModel(
        isPlayersChanged: Bool
    ) -> GameVideoViewLayout.ViewModel {
        .init(
            state: .waiting,
            accountId: accountId,
            waitingCountdown: nil,
            orderedPlayers: [],
            gestureAcceptanceTier: .none,
            isPlayersChanged: isPlayersChanged,
            subroundsCount: 0,
            currentSubroundCount: 0,
            timerInfo: .empty(),
            isOwnHosting: false,
            tooltipViewModel: nil
        )
    }

    func makePreparingViewModel(
        input: Input,
        info: GameStateMachine.PreparingInfo
    ) -> GameVideoViewLayout.ViewModel {
        .init(
            state: .waiting,
            accountId: accountId,
            waitingCountdown: makeWaitingCountdown(gameDate: info.gameDate),
            orderedPlayers: [],
            gestureAcceptanceTier: .none,
            isPlayersChanged: input.isPlayersChanged,
            subroundsCount: info.subroundsCount ?? 0,
            currentSubroundCount: 0,
            timerInfo: .empty(),
            isOwnHosting: false,
            tooltipViewModel: nil
        )
    }

    func makeRoundViewModel(
        input: Input,
        round: GameStateMachine.Round,
        roundsInfo: GameStateMachine.RoundsInfo
    ) -> GameVideoViewLayout.ViewModel {
        let isOwnHosting = makeIsOwnHosting(round: round)
        let orderedPlayers = makeOrderedPlayers(
            round: round,
            rtcIceConnectedFlags: input.rtcIceConnectedFlags,
            voting: input.voting,
            bannedPlayers: input.bannedPlayers
        )

        let tooltipViewModel = makeTooltipModel(
            round: round,
            roundsInfo: roundsInfo,
            isOwnHosting: isOwnHosting,
            isPlayerTooltipShown: input.isPlayerTooltipShown,
            isSwipeTooltipShown: input.isSwipeTooltipShown
        )

        return .init(
            state: makeState(round: round),
            accountId: accountId,
            waitingCountdown: nil,
            orderedPlayers: orderedPlayers,
            gestureAcceptanceTier: makeGestureAcceptanceTier(
                gestureAcceptances: input.gestureAcceptances,
                players: orderedPlayers
            ),
            isPlayersChanged: input.isPlayersChanged,
            subroundsCount: roundsInfo.subroundsCount,
            currentSubroundCount: roundsInfo.subroundIndex + 1,
            timerInfo: makeTimerInfo(round: round),
            isOwnHosting: isOwnHosting,
            tooltipViewModel: tooltipViewModel
        )
    }

    func makeWaitingCountdown(gameDate: Date?) -> GameVideoViewLayout.ViewModel.WaitingCountdown? {
        guard let gameDate else {
            return nil
        }

        return .init(
            text: countdownDateFormatter
                .formatCompact(to: gameDate),
            secondsRemaining: max(0, Int(gameDate.timeIntervalSinceNow))
        )
    }

    func makeState(
        round: GameStateMachine.Round
    ) -> GameVideoViewLayout.State {
        switch round.state {
        case let .hosting(hosting):
            makeState(hosting: hosting)
        }
    }

    func makeState(
        hosting: GameStateMachine.Hosting
    ) -> GameVideoViewLayout.State {
        switch hosting.state {
        case .transition:
            .subroundStart
        case .introduction:
            .hostIntroduction
        case .gameplay:
            .hosting
        case .end:
            .hostingEnd
        }
    }

    func makeOrderedPlayers(
        round: GameStateMachine.Round,
        rtcIceConnectedFlags: [AccountId: Bool],
        voting: GameVideoVoting?,
        bannedPlayers: Set<AccountId>
    ) -> [GameVideoViewLayout.Player] {
        var result = [GameVideoViewLayout.Player]()
        // creates host player model
        let firstCachedAccountId = firstCachedAccoundId(
            addingPlayerTo: &result,
            round: round,
            rtcIceConnectedFlags: rtcIceConnectedFlags,
            bannedPlayers: bannedPlayers
        )

        let isHostDisconnected = result.first(where: { $0.isHost })?.rendererState == .disconnected

        // creates Self player model if needed
        let secondCachedAccountId = secondCachedAccoundId(
            addingPlayerTo: &result,
            rendererState: isHostDisconnected ? .suspended : .connected
        )

        let prefilledAccountIds = Set([
            firstCachedAccountId,
            secondCachedAccountId
        ].compactMap { $0 })

        for player in round.players {
            if prefilledAccountIds.contains(player) {
                continue
            }
            let isLocal = player == accountId

            let votingState = makeVotingState(
                voting: voting,
                player: player
            )

            let rendererState = isHostDisconnected ? .suspended : makeRendererState(
                isLocal: isLocal,
                player: player,
                rtcIceConnectedFlags: rtcIceConnectedFlags,
                votingState: votingState
            )

            let interactedWithPlayers = voting?.interactedWithPlayers ?? []

            let filtersConfiguration = makeFiltersConfiguration(
                for: player,
                round: round,
                isLocal: isLocal,
                votingState: votingState,
                rendererState: rendererState
            )

            let attestationOverlayModel = isHostDisconnected || bannedPlayers.contains(player)
                ? .empty
                : makeAttestationModel(
                    for: player,
                    round: round,
                    isLocal: isLocal,
                    votingState: votingState,
                    interactedWithPlayers: interactedWithPlayers,
                    rendererState: rendererState
                )

            result.append(.init(
                accountId: player,
                votingState: votingState,
                isHost: false,
                isLocal: isLocal,
                isBanned: bannedPlayers.contains(player),
                rendererState: rendererState,
                filtersConfiguration: filtersConfiguration,
                attestationOverlayModel: attestationOverlayModel
            ))
        }

        return result
    }

    func firstCachedAccoundId(
        addingPlayerTo result: inout [GameVideoViewLayout.Player],
        round: GameStateMachine.Round,
        rtcIceConnectedFlags: [AccountId: Bool],
        bannedPlayers: Set<AccountId>
    ) -> AccountId? {
        guard result.isEmpty else {
            return nil
        }
        if case let .hosting(hosting) = round.state {
            let hostAccountId = hosting.host
            let isLocal = hostAccountId == accountId
            let rendererState = makeRendererState(
                isLocal: isLocal,
                player: hostAccountId,
                rtcIceConnectedFlags: rtcIceConnectedFlags,
                votingState: .notDecided
            )
            result.append(.init(
                accountId: hostAccountId,
                votingState: .notDecided,
                isHost: true,
                isLocal: isLocal,
                isBanned: bannedPlayers.contains(hosting.host),
                rendererState: rendererState,
                filtersConfiguration: .original, // alway original for host
                attestationOverlayModel: .empty
            ))
            return hostAccountId
        } else {
            result.append(.defaultLocal(accountId: accountId))
            return accountId
        }
    }

    func secondCachedAccoundId(
        addingPlayerTo result: inout [GameVideoViewLayout.Player],
        rendererState: GameVideoViewLayout.RendererState
    ) -> AccountId? {
        guard
            result.count == 1,
            result[0].accountId != accountId
        else {
            return nil
        }
        result.append(.defaultLocal(
            accountId: accountId,
            rendererState: rendererState
        ))
        return accountId
    }

    func makeRendererState(
        isLocal: Bool,
        player: AccountId,
        rtcIceConnectedFlags: [AccountId: Bool],
        votingState: GameVideoVotingState
    ) -> GameVideoViewLayout.RendererState {
        guard !isLocal else {
            return .connected
        }

        let connectionPossible = rtcIceConnectedFlags[player] == true
        if connectionPossible {
            // Freeze only on a positive (green) vote, negatives and auto-rejection keep the stream live
            return votingState == .positive ? .suspended : .connected
        } else {
            return .disconnected
        }
    }

    func makeVotingState(
        voting: GameVideoVoting?,
        player: AccountId
    ) -> GameVideoVotingState {
        guard let state = voting?.statesByPlayer[player] else {
            return .notDecided
        }
        return state
    }

    func makeTimerInfo(
        round: GameStateMachine.Round
    ) -> GameVideoViewLayout.TimerInfo {
        guard case let .hosting(hosting) = round.state else {
            return .empty()
        }
        switch hosting.state {
        case let .transition(left, total),
             let .gameplay(left, total):
            let leftInt = Int(left)
            return leftInt > 0
                ? .init(
                    counter: leftInt,
                    progress: 1 - CGFloat(left / total)
                )
                : .empty()
        case .introduction,
             .end:
            return .empty()
        }
    }

    func makeIsOwnHosting(
        round: GameStateMachine.Round
    ) -> Bool {
        guard case let .hosting(hosting) = round.state else {
            return false
        }
        return hosting.host == accountId
    }

    func makeGestureAcceptanceTier(
        gestureAcceptances: Set<AccountId>,
        players: [GameVideoViewLayout.Player]
    ) -> GameVideoViewLayout.GestureAcceptanceTier {
        guard players.first(where: \.isLocal)?.isHost == false else {
            return .none
        }

        guard let hostId = players.first(where: \.isHost) else {
            return .none
        }

        let hostAccepted = gestureAcceptances.contains(hostId.accountId)
        let eligiblePlayerAcceptors = players.filter { !$0.isLocal && !$0.isHost }
        let playerAcceptancesCount = gestureAcceptances.filter { $0 != hostId.accountId }.count

        guard hostAccepted || playerAcceptancesCount > 0 else {
            return .none
        }

        let hostLevelValue = 40.0
        let playersLevelTargetSum = 100.0 - hostLevelValue

        let hostLevel = hostAccepted ? hostLevelValue : 0.0
        let playersLevel =
            if eligiblePlayerAcceptors.isEmpty {
                hostAccepted ? playersLevelTargetSum : 0
            } else {
                Double(playerAcceptancesCount) / Double(eligiblePlayerAcceptors.count) * playersLevelTargetSum
            }

        let level = Int(ceil(hostLevel + playersLevel))
        return .level(min(level, 100))
    }

    func makeTooltipModel(
        round: GameStateMachine.Round,
        roundsInfo: GameStateMachine.RoundsInfo,
        isOwnHosting: Bool,
        isPlayerTooltipShown: Bool,
        isSwipeTooltipShown: Bool
    ) -> GameVideoTooltipView.ViewModel? {
        // Only show tooltips during gameplay state in first round
        guard
            roundsInfo.subroundIndex == 0,
            case let .hosting(hosting) = round.state,
            case let .gameplay(left, total) = hosting.state
        else { return nil }

        guard isPlayerTooltipShown else {
            // player tooltip (show gesture / copy host) - appears at start of gameplay
            return isOwnHosting ? .showGesture : .copyHost
        }

        guard isSwipeTooltipShown else {
            // Swipe tooltip - appears in the middle of gameplay
            let middle = total / 2
            return left <= middle ? .swipeHint : nil
        }

        return nil
    }
}
