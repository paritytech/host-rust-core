import Foundation
import SubstrateSdk

public extension NewAirdropPallet {
    struct WinnersKey: JSONListConvertible, Hashable {
        public let eventId: EventId
        public let entry: RegistrationEntry

        public init(eventId: EventId, entry: RegistrationEntry) {
            self.eventId = eventId
            self.entry = entry
        }

        public init(jsonList: [JSON], context: [CodingUserInfoKey: Any]?) throws {
            guard jsonList.count == 2 else {
                throw JSONListConvertibleError.unexpectedNumberOfItems(
                    expected: 2,
                    actual: jsonList.count
                )
            }

            eventId = try jsonList[0].map(to: BytesCodable.self, with: context).wrappedValue
            entry = try jsonList[1].map(to: RegistrationEntry.self, with: context)
        }
    }
}
