import Foundation
import Individuality

protocol DIM1BackgroundStateFactoryProtocol {
    func makeState(candidate: ProofOfInkPallet.Candidate?) -> DIM1BackgroundSyncState
}

final class DIM1BackgroundStateFactory: DIM1BackgroundStateFactoryProtocol {
    func makeState(candidate: ProofOfInkPallet.Candidate?) -> DIM1BackgroundSyncState {
        guard let candidate else {
            return .none
        }

        switch candidate {
        case .applied:
            return .none
        case let .selected(selected):
            return makeState(selected: selected)
        case .proven:
            return .videoReviewed
        }
    }

    private func makeState(selected: ProofOfInkPallet.Candidate.Selected) -> DIM1BackgroundSyncState {
        switch selected.allocation {
        case .initial:
            selected.judging == nil
                ? .photoSubmission
                : .photoInReview
        case .initDone:
            .photoReviewed
        case .full:
            selected.judging == nil
                ? .videoSubmission
                : .videoInReview
        }
    }
}
