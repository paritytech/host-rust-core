import Foundation
import Foundation_iOS
import CommonService

final class EvidenceSubmissionStateStore: BaseObservableStateStore<EvidenceSubmission.RemoteState> {}

extension EvidenceSubmissionStateStore: PersonhoodRegistrationSyncObserver {
    func personhoodRegistrationSyncChanged(by change: PersonhoodRegistrationSyncChange) {
        mutex.lock()

        defer {
            mutex.unlock()
        }

        if let state = stateObservable.state {
            stateObservable.state = state.applyingPeopleChange(from: change)
        } else {
            guard case let .defined(candidate) = change.proofOfInkCandidate else {
                logger.warning("Change doesn't include all the data: \(change)")
                return
            }

            stateObservable.state = .init(
                candidate: candidate,
                transactionStorageAuthorizations: nil,
                bulletInBlockNumber: nil
            )
        }
    }
}

extension EvidenceSubmissionStateStore: TattooUploadingBulletInSyncObserver {
    func tattooUploadingBulletInSyncChanged(by change: TattooUploadingBulletInSyncChange) {
        mutex.lock()

        defer {
            mutex.unlock()
        }

        if let state = stateObservable.state {
            stateObservable.state = state.applyingBulletInChange(from: change)
        } else {
            guard
                case let .defined(authorizations) = change.authorizations,
                case let .defined(blockNumber) = change.blockNumber else {
                logger.warning("Change doesn't include all the data: \(change)")
                return
            }

            stateObservable.state = .init(
                candidate: nil,
                transactionStorageAuthorizations: authorizations,
                bulletInBlockNumber: blockNumber
            )
        }
    }
}
