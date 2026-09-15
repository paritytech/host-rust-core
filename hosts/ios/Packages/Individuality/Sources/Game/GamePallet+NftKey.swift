import Foundation
import SubstrateSdk

public extension GamePallet {
    struct NftKey: Hashable, JSONListConvertible {
        public let hash: Data

        public init(hash: Data) {
            self.hash = hash
        }

        public init(jsonList: [JSON], context: [CodingUserInfoKey: Any]?) throws {
            guard jsonList.count == 2 else {
                throw JSONListConvertibleError.unexpectedNumberOfItems(
                    expected: 2,
                    actual: jsonList.count
                )
            }

            hash = try jsonList[1].map(to: BytesCodable.self, with: context).wrappedValue
        }
    }
}
