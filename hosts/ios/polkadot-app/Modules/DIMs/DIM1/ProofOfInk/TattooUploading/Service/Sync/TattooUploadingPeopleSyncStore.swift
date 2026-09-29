import Foundation
import CommonService

final class TattooUploadingPeopleSyncStore: BaseObservableStateStore<PersonhoodRegistrationSyncState> {}

extension TattooUploadingPeopleSyncStore: PersonhoodRegistrationSyncObserver {
    func personhoodRegistrationSyncChanged(by change: PersonhoodRegistrationSyncChange) {
        mutex.lock()

        defer {
            mutex.unlock()
        }

        if let state = stateObservable.state {
            stateObservable.state = state.applying(change: change)
        } else {
            guard
                case let .defined(mobRuleAlias) = change.mobRuleAlias,
                case let .defined(scoreAlias) = change.scoreAlias,
                case let .defined(resourcesAlias) = change.resourcesAlias,
                case let .defined(personalId) = change.personalId
            else {
                logger.warning("Change fields undefined: \(change)")
                return
            }

            stateObservable.state = .init(
                personalId: personalId,
                mobRuleAlias: mobRuleAlias,
                scoreAlias: scoreAlias,
                resourcesAlias: resourcesAlias,
                memberRingPosition: change.memberRingPosition.value ?? nil
            )
        }
    }
}
