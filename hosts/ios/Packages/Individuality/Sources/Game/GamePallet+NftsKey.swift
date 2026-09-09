import Foundation
import SubstrateSdk

public extension GamePallet {
    typealias NftHash = Data

    struct NftsKey: JSONListConvertible, Hashable {
        public let hash: NftHash

        public init(hash: NftHash) {
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
