import Foundation
import SubstrateSdk

extension GamePallet.AccountOrPerson: ScaleEncodable {
    public func encode(scaleEncoder: any ScaleEncoding) throws {
        switch self {
        case let .account(accountId):
            try UInt8(0).encode(scaleEncoder: scaleEncoder)
            scaleEncoder.appendRaw(data: accountId)
        case let .person(alias):
            try UInt8(1).encode(scaleEncoder: scaleEncoder)
            scaleEncoder.appendRaw(data: alias)
        }
    }
}
