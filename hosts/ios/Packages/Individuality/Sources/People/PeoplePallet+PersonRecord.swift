import Foundation
import SubstrateSdk

public extension PeoplePallet {
    struct PersonRecord: Decodable, Equatable {
        @OptionalBytesCodable
        public var account: AccountId?
    }
}
