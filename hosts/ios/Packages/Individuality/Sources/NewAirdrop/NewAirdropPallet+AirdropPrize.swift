import Foundation
import SubstrateSdk
import BigInt

public extension NewAirdropPallet {
    struct AirdropPrize: Decodable, Equatable {
        public let assetId: JSON
        @StringCodable public var assetAmount: AssetBalance
        @StringCodable public var maxWinners: UInt32
        @StringCodable public var winnerCap: Permill
    }
}
