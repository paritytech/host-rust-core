import Foundation
import SubstrateSdk
import Individuality

protocol ProofOfInkChatEvidenceModelFactoryProtocol {
    func makeViewModel(input: ProofOfInkChatEvidenceModelFactoryInput) -> ProofOfInkChatEvidenceModel?
}

struct ProofOfInkChatEvidenceModelFactoryInput {
    let remoteState: DetermineStateSyncState?
    let evidenceSession: EvidenceSubmission.Session?
}

final class ProofOfInkChatEvidenceModelFactory: ProofOfInkChatEvidenceModelFactoryProtocol {
    func makeViewModel(input: ProofOfInkChatEvidenceModelFactoryInput) -> ProofOfInkChatEvidenceModel? {
        guard let remoteState = input.remoteState,
              let candidate = remoteState.candidate,
              case let .selected(selectedState) = candidate else {
            return nil
        }

        return ProofOfInkChatEvidenceModel(
            photoItem: makePhotoItem(
                selected: selectedState,
                input: input
            ),
            videoItem: makeVideoItem(
                selected: selectedState,
                input: input
            )
        )
    }

    private func makePhotoItem(
        selected: ProofOfInkPallet.Candidate.Selected,
        input: ProofOfInkChatEvidenceModelFactoryInput
    ) -> ProofOfInkChatEvidenceItemModel {
        switch selected.allocation {
        case .initial:
            if selected.judging != nil {
                return makeInReviewState()
            }
            guard let session = input.evidenceSession else {
                return .init(
                    state: .waitingToUpload
                )
            }
            return makeInProgressState(evidenceSession: session)
        case .initDone,
             .full:
            return .init(
                state: .reviewed
            )
        }
    }

    private func makeVideoItem(
        selected: ProofOfInkPallet.Candidate.Selected,
        input: ProofOfInkChatEvidenceModelFactoryInput
    ) -> ProofOfInkChatEvidenceItemModel {
        switch selected.allocation {
        case .initial:
            return .init(
                state: .waitingToUpload
            )
        case .initDone,
             .full:
            if selected.judging != nil {
                return makeInReviewState()
            }
            guard let session = input.evidenceSession else {
                return .init(
                    state: .waitingToUpload
                )
            }
            return makeInProgressState(evidenceSession: session)
        }
    }

    private func makeInReviewState() -> ProofOfInkChatEvidenceItemModel {
        .init(
            state: .inReview
        )
    }

    private func makeInProgressState(
        evidenceSession: EvidenceSubmission.Session
    ) -> ProofOfInkChatEvidenceItemModel {
        if evidenceSession.error != nil {
            return .init(
                state: .uploadingFailed
            )
        }
        switch evidenceSession.progress {
        case .waiting,
             nil:
            return .init(
                state: .waitingToUpload
            )
        case let .submitting(submitting):
            let floatProgress = submitting.totalChunks > 0
                ? CGFloat(submitting.chunkIndex + 1) / CGFloat(submitting.totalChunks)
                : 1.0
            let progress = UInt8(floatProgress * 100)
            return .init(
                state: .uploading(progress: progress)
            )
        case .completing:
            return .init(
                state: .uploading(progress: 100)
            )
        case .allocatingFull:
            return .init(
                state: .requestingStorage
            )
        }
    }
}
