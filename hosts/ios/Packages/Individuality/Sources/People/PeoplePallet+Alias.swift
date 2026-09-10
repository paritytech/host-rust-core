import Foundation
import SubstrateSdk

public extension PeoplePallet {
    struct RevisedContextualAlias: Decodable, Equatable {
        enum CodingKeys: String, CodingKey {
            case revision
            case ring
            case contextualAlias = "ca"
        }

        @StringCodable public var revision: MembersPallet.RevisionIndex
        @StringCodable public var ring: MembersPallet.RingIndex
        public let contextualAlias: ContextualAlias

        public var alias: Data { contextualAlias.alias }
    }

    struct ContextualAlias: Hashable, Codable {
        @BytesCodable public var alias: Data
    }
}

public extension PeoplePallet.RevisedContextualAlias {
    func isRelevant(accordingTo memberRingPosition: MembersPallet.RingPosition) -> Bool {
        ring == memberRingPosition.ringIndex
    }
}

public extension PeoplePallet.RevisedContextualAlias? {
    func isRelevant(accordingTo memberRingPosition: MembersPallet.RingPosition) -> Bool {
        switch self {
        case .none:
            false
        case let .some(wrapped):
            wrapped.isRelevant(accordingTo: memberRingPosition)
        }
    }
}
