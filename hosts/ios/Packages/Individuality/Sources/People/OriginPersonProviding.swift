import Foundation
import SubstrateSdk
import KeyDerivation

public protocol OriginPersonProviding {
    func pickPersonOrigin() async throws -> PersonOrigin
    func pickPersonOrigins() async throws -> [PersonOrigin]
}

public enum OriginPersonProviderError: Error {
    case noPersonsExist
}

// Returns all origins the person is a member of, full first. Checks ring status of both lite and full person.
public final class OriginPersonProvider {
    let liteVrfManager: BandersnatchKeyManaging
    let liteCollectionId: MembersPallet.CollectionIdentifier
    let fullVrfManager: BandersnatchKeyManaging
    let fullCollectionId: MembersPallet.CollectionIdentifier
    let memberStatusChecker: MembershipStatusChecking

    public init(
        liteVrfManager: BandersnatchKeyManaging,
        liteCollectionId: MembersPallet.CollectionIdentifier,
        fullVrfManager: BandersnatchKeyManaging,
        fullCollectionId: MembersPallet.CollectionIdentifier,
        memberStatusChecker: MembershipStatusChecking
    ) {
        self.liteVrfManager = liteVrfManager
        self.liteCollectionId = liteCollectionId
        self.fullVrfManager = fullVrfManager
        self.fullCollectionId = fullCollectionId
        self.memberStatusChecker = memberStatusChecker
    }
}

extension OriginPersonProvider: OriginPersonProviding {
    public func pickPersonOrigins() async throws -> [PersonOrigin] {
        let fullMemberKey = try fullVrfManager.getMemberKey()
        let liteMemberKey = try liteVrfManager.getMemberKey()

        let statuses = try await memberStatusChecker.checkStatuses(
            of: [
                .init(memberKey: fullMemberKey, collection: fullCollectionId),
                .init(memberKey: liteMemberKey, collection: liteCollectionId),
            ],
            blockHash: nil
        )

        var origins: [PersonOrigin] = []

        if let fullRingIndex = statuses[fullMemberKey] {
            origins.append(.full(fullRingIndex, fullVrfManager))
        }

        if let liteRingIndex = statuses[liteMemberKey] {
            origins.append(.lite(liteRingIndex, liteVrfManager))
        }

        guard !origins.isEmpty else {
            throw OriginPersonProviderError.noPersonsExist
        }

        return origins
    }

    public func pickPersonOrigin() async throws -> PersonOrigin {
        guard let origin = try await pickPersonOrigins().first else {
            throw OriginPersonProviderError.noPersonsExist
        }
        return origin
    }
}
