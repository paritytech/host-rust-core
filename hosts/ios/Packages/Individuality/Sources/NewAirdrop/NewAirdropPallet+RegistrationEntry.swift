import Foundation
import SubstrateSdk

public extension NewAirdropPallet {
    enum RegistrationEntry: Decodable, Hashable {
        case alias(participantOrigin: Data)
        case account(accountId: AccountId)

        public init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            let variant = try container.decode(String.self)

            switch variant {
            case "Alias":
                let payload = try container.decode(AliasPayload.self)
                self = .alias(participantOrigin: payload.participantOrigin)
            case "Account":
                let payload = try container.decode(AccountPayload.self)
                self = .account(accountId: payload.accountId)
            default:
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unsupported RegistrationEntry variant: \(variant)"
                )
            }
        }

        private struct AliasPayload: Decodable {
            @BytesCodable var participantOrigin: Data
        }

        private struct AccountPayload: Decodable {
            @BytesCodable var accountId: AccountId
        }
    }
}

public extension NewAirdropPallet.RegistrationEntry {
    /// SCALE-encoded registration entry used as the message of the alias membership proof.
    ///
    /// Mirrors the runtime variant order (`Alias = 0`, `Account = 1`): `0x00 ++ alias` for an
    /// alias-based player, `0x01 ++ account_id` for an account-based player.
    static func proofMessage(for who: GamePallet.AccountOrPerson) -> Data {
        switch who {
        case let .person(alias):
            Data([0x00]) + alias
        case let .account(accountID):
            Data([0x01]) + accountID
        }
    }
}
