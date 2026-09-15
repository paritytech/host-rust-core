import Foundation
import QuartzCore
import UIKit
import SubstrateSdk

extension GameVideoViewModelFactory {
    func makeAttestationModel(
        for player: AccountId,
        round: GameStateMachine.Round,
        isLocal: Bool,
        votingState: GameVideoVotingState,
        interactedWithPlayers: Set<AccountId>,
        rendererState: GameVideoViewLayout.RendererState
    ) -> AttestationOverlayView.ViewModel {
        let attested: Bool? =
            switch votingState {
            case .negative: false
            case .positive: true
            case .notDecided: nil
            }

        let uiAvailable = attestationUIAvailable(
            for: player,
            round: round,
            isLocal: isLocal,
            rendererState: rendererState
        )

        let interactionsEnabled = uiAvailable
            ? shouldAllowVotingInteractions(
                for: player,
                round: round,
                isLocal: isLocal
            )
            : false

        let dragHintEnabled = interactionsEnabled
            ? shouldShowDragHint(
                for: player,
                round: round,
                interactedWithPlayers: interactedWithPlayers,
                isLocal: isLocal
            )
            : false

        let autoDiscardSpan = autoDiscardSpan(
            votingState: votingState,
            for: round
        )

        return AttestationOverlayView.ViewModel(
            attested: attested,
            uiAvailable: uiAvailable,
            interactionsEnabled: interactionsEnabled,
            dragHintEnabled: dragHintEnabled,
            autoDiscardSpan: autoDiscardSpan
        )
    }

    func shouldAllowVotingInteractions(
        for player: AccountId,
        round: GameStateMachine.Round,
        isLocal: Bool
    ) -> Bool {
        if isLocal {
            return false
        }

        guard case let .hosting(hosting) = round.state else {
            return false
        }

        if hosting.host == player {
            return false
        }

        switch hosting.state {
        case .gameplay,
             .end:
            return true
        default:
            return false
        }
    }

    func autoDiscardSpan(
        votingState: GameVideoVotingState?,
        for round: GameStateMachine.Round
    ) -> AnimationSpan? {
        switch votingState ?? .notDecided {
        case .positive,
             .negative:
            nil

        case .notDecided:
            computeAnimatedFillTiming(round: round)
        }
    }

    func shouldShowDragHint(
        for player: AccountId,
        round: GameStateMachine.Round,
        interactedWithPlayers: Set<AccountId>,
        isLocal: Bool
    ) -> Bool {
        if isLocal {
            return false
        }

        if case let .hosting(hosting) = round.state,
           case .gameplay = hosting.state,
           !interactedWithPlayers.contains(player) {
            return true
        }

        return false
    }
}
