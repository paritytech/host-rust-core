import Foundation
import SubstrateSdk

public extension NewAirdropPallet {
    struct RegistrationsKey: JSONListConvertible, Hashable {
        public let eventId: EventId
        public let ticket: Data

        public init(eventId: EventId, ticket: Data) {
            self.eventId = eventId
            self.ticket = ticket
        }

        public init(jsonList: [JSON], context: [CodingUserInfoKey: Any]?) throws {
            guard jsonList.count == 2 else {
                throw JSONListConvertibleError.unexpectedNumberOfItems(
                    expected: 2,
                    actual: jsonList.count
                )
            }

            eventId = try jsonList[0].map(to: BytesCodable.self, with: context).wrappedValue
            ticket = try jsonList[1].map(to: BytesCodable.self, with: context).wrappedValue
        }
    }
}
