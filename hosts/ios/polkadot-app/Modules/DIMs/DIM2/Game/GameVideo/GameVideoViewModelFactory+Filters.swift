import Foundation
import QuartzCore
import UIKit
import SubstrateSdk

extension GameVideoViewModelFactory {
    func makeFiltersConfiguration(
        for player: AccountId,
        round: GameStateMachine.Round,
        isLocal: Bool,
        votingState: GameVideoVotingState?,
        rendererState: GameVideoViewLayout.RendererState
    ) -> FilteredRendererConfiguration {
        guard attestationUIAvailable(
            for: player,
            round: round,
            isLocal: isLocal,
            rendererState: rendererState
        ) else {
            return .original
        }

        switch votingState ?? .notDecided {
        case .positive:
            let provider = PlayerAttestedFilterProvider()

            return .init(
                overlayProviders: [],
                lookProviders: [provider],
                spatialEffectProvider: nil
            )

        case .negative:
            let notAttestedProvider = PlayerNotAttestedFilterProvider()

            return .init(
                overlayProviders: [notAttestedProvider],
                lookProviders: [notAttestedProvider],
                spatialEffectProvider: notAttestedProvider
            )

        case .notDecided:
            // overlay currently disabled (polishing needed)
            return .original
//            guard !interactedWithPlayers.contains(player),
//                  let timing = computeAnimatedFillTiming(round: round) else {
//                return .original
//            }
//            let overlay = makeInactivityOverlay(for: timing)
//            return .init(
//                overlayProviders: [overlay],
//                lookProviders: [],
//                spatialEffectProvider: nil
//            )
        }
    }

    //    func makeInactivityOverlay(for timing: AnimationSpan) -> OverlayFilterProvider {
    //        let color = (UIColor(hex: "#FF2D55") ?? .red).withAlphaComponent(0.16)
    //        return AnimatedOverlayProvider(
    //            startsAt: timing.startsAt,
    //            direction: .rightToLeft,
    //            duration: timing.duration,
    //            color: color,
    //            cornerMask: [
    //                .layerMinXMinYCorner,
    //                .layerMinXMaxYCorner
    //            ],
    //            radius: 0.2 // TODO: compute
    //        )
    //    }

    func computeAnimatedFillTiming(round: GameStateMachine.Round) -> AnimationSpan? {
        guard case let .hosting(hosting) = round.state,
              case let .gameplay(left, total) = hosting.state,
              total > 0 else {
            return nil
        }
        let now = CACurrentMediaTime()

        let timeLeft = max(0, left)
        let totalTime = max(0, total)
        let timeElapsed = totalTime - timeLeft
        let roundBeginning = now - timeElapsed
        let halfSpan = totalTime / 2

        // TODO: Find way to add property "let startsAt: CFAbsoluteTime" to GameStateMachine.Round
        // Align to base frame duration to avoid floating point noise (fix of duplicate launches)
        let startsAt = roundBeginning + halfSpan
        let startsAtRounded = startsAt.rounded(milliseconds: 100)

        return .init(
            startsAt: startsAtRounded,
            duration: halfSpan
        )
    }

    func attestationUIAvailable(
        for player: AccountId,
        round: GameStateMachine.Round,
        isLocal: Bool,
        rendererState: GameVideoViewLayout.RendererState
    ) -> Bool {
        if isLocal {
            return false
        }

        if rendererState == .disconnected {
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
}
