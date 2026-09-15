import Foundation
import Individuality

protocol PersonRegistrationStateFactoryProtocol {
    func makeState(
        remoteState: PersonhoodRegistrationSyncState?,
        memberRingPosition: MembersPallet.RingPosition?,
        keysStatus: MembersPallet.RingKeysStatus?
    ) -> PersonRegistrationSyncState?
}

final class PersonRegistrationStateFactory: PersonRegistrationStateFactoryProtocol {
    func makeState(
        remoteState: PersonhoodRegistrationSyncState?,
        memberRingPosition: MembersPallet.RingPosition?,
        keysStatus: MembersPallet.RingKeysStatus?
    ) -> PersonRegistrationSyncState? {
        guard let remoteState else {
            return nil
        }

        if remoteState.hasRelevantAliases {
            return .aliasAssigned
        }

        if let memberRingPosition, let keysStatus, keysStatus.includesKey(from: memberRingPosition) {
            return .personAdded
        }

        if remoteState.personalId != nil {
            return .personRegistered
        }

        return nil
    }
}
