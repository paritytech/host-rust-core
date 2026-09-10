import Foundation
import SubstrateSdk

public extension GamePallet {
    enum AccountOrPerson: Codable, Equatable {
        private enum RawType: String, Codable {
            case account = "Account"
            case person = "Person"
        }

        case account(accountID: AccountId)
        case person(alias: Data)

        public init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()

            let type = try container.decode(RawType.self)

            switch type {
            case .account:
                let accountId = try container.decode(BytesCodable.self)
                self = .account(accountID: accountId.wrappedValue)
            case .person:
                let alias = try container.decode(BytesCodable.self)
                self = .person(alias: alias.wrappedValue)
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.unkeyedContainer()

            switch self {
            case let .account(accountId):
                try container.encode(RawType.account.rawValue)
                try container.encode(BytesCodable(wrappedValue: accountId))
            case let .person(alias):
                try container.encode(RawType.person.rawValue)
                try container.encode(BytesCodable(wrappedValue: alias))
            }
        }
    }
}

public extension GamePallet.AccountOrPerson {
    var rawTypeValue: String {
        switch self {
        case .account:
            RawType.account.rawValue
        case .person:
            RawType.person.rawValue
        }
    }
}
