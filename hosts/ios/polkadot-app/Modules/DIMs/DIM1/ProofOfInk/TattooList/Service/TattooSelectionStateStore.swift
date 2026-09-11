import Foundation
import Foundation_iOS
import CommonService

final class TattooSelectionStateStore: BaseObservableStateStore<TattooSelectionState> {}

extension TattooSelectionStateStore: TattooSelectionSyncServiceObserver {
    func tattooSelectionStateChanged(by change: TattooSelectionStateChange) {
        mutex.lock()

        defer {
            mutex.unlock()
        }

        if let state = stateObservable.state {
            stateObservable.state = state.applying(change: change)
        } else {
            guard
                case let .defined(candidate) = change.candidate,
                case let .defined(account) = change.account,
                case let .defined(personalId) = change.personalId else {
                logger.warning("Change doesn't include all the data: \(change)")
                return
            }

            stateObservable.state = .init(
                candidate: candidate,
                account: account,
                personalId: personalId
            )
        }
    }
}
