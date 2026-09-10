import Foundation
import SubstrateSdk

public extension NewAirdropPallet {
    struct ActiveEvent: Decodable, Equatable {
        @BytesCodable public var id: EventId
        public let info: EventInfo
        public let status: Status
    }
}
