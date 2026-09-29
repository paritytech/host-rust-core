import Foundation
import SubstrateSdk

public extension NewAirdropPallet {
    struct EventInfo: Decodable, Equatable {
        public let prize: AirdropPrize
        @StringCodable public var registrationStarts: UInt64
        @StringCodable public var drawTime: UInt64
        @StringCodable public var endTime: UInt64
    }
}
