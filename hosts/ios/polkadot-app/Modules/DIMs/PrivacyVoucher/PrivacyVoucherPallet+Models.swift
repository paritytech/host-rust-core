import Foundation
import SubstrateSdk
import SubstrateStorageQuery
import Individuality
import BigInt

extension PrivacyVoucherPallet {
    typealias MemberIndex = UInt32
    typealias MemberKey = Data
    typealias Voucher = Data
    typealias Proof = Data
    typealias VoucherPrivateKey = Data
    typealias VoucherId = UInt32

    struct KeysToRing: Decodable, Equatable, Hashable {
        let balanceOf: Balance
        let ringIndex: MembersPallet.RingIndex

        init(balanceOf: Balance, ringIndex: MembersPallet.RingIndex) {
            self.balanceOf = balanceOf
            self.ringIndex = ringIndex
        }

        init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()

            balanceOf = try container.decode(StringScaleMapper<Balance>.self).value
            ringIndex = try container.decode(StringScaleMapper<MembersPallet.RingIndex>.self).value
        }
    }

    struct ClaimableRing: Decodable {
        @BytesCodable var root: Data
        @StringCodable var builtBlockNumber: BlockNumber
    }

    struct BuildingRing: Decodable {
        @BytesCodable var intermediate: Data
        @StringCodable var index: MembersPallet.RingIndex
    }

    struct UsedTicket: Decodable {}

    struct UsedTicketKey: NMapKeyStorageKeyProtocol {
        let balanceOf: Balance
        let ringIndex: MembersPallet.RingIndex
        let alias: Data

        func appendSubkey(to encoder: DynamicScaleEncoding, type: String, index: Int) throws {
            switch index {
            case 0:
                try encoder.append(StringCodable(wrappedValue: balanceOf), ofType: type)
            case 1:
                try encoder.append(StringCodable(wrappedValue: ringIndex), ofType: type)
            case 2:
                try encoder.append(BytesCodable(wrappedValue: alias), ofType: type)
            default:
                break
            }
        }
    }

    enum VoucherType: Decodable {
        case fixed(Balance)
        case variable(Data)

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()

            let type = try container.decode(String.self)

            switch type {
            case "Fixed":
                let amount = try container.decode(StringScaleMapper<Balance>.self).value
                self = .fixed(amount)
            case "Variable":
                let voucherId = try container.decode(BytesCodable.self).wrappedValue
                self = .variable(voucherId)
            default:
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Unsupported voucher type \(type)"
                    )
                )
            }
        }
    }
}
