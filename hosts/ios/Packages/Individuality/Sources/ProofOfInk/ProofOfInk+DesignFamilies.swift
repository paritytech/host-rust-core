import Foundation
import SubstrateSdk

public extension ProofOfInkPallet {
    typealias FamilyIndex = UInt16
    typealias DesignIndex = UInt16
    typealias VariantIndex = UInt8
    typealias FamilyId = Data
    typealias ProceduralSeed = Data

    struct Family: Decodable, Equatable {
        public let kind: FamilyKind
        @BytesCodable public var id: FamilyId
    }

    enum FamilyKind: Decodable, Equatable {
        private enum FamilyKindVariant: String, Codable {
            case designed = "Designed"
            case procedural = "Procedural"
            case proceduralAccount = "ProceduralAccount"
            case proceduralPersonal = "ProceduralPersonal"
        }

        public struct Designed: Decodable, Equatable {
            @StringCodable public var count: DesignIndex
        }

        public struct Procedural: Decodable, Equatable {
            @StringCodable public var range: VariantIndex
        }

        case designed(Designed)
        case procedural(Procedural)
        case proceduralAccount
        case proceduralPersonal
        case unsupported(String)

        public init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            let type = try container.decode(String.self)
            if let supportedType = FamilyKindVariant(rawValue: type) {
                switch supportedType {
                case .designed:
                    let model = try container.decode(Designed.self)
                    self = .designed(model)
                case .procedural:
                    let model = try container.decode(Procedural.self)
                    self = .procedural(model)
                case .proceduralAccount:
                    self = .proceduralAccount
                case .proceduralPersonal:
                    self = .proceduralPersonal
                }
            } else {
                self = .unsupported(type)
            }
        }
    }

    struct DesignFamiliesKey: JSONListConvertible, Hashable {
        public let index: FamilyIndex

        public init(index: FamilyIndex) {
            self.index = index
        }

        public init(jsonList: [JSON], context: [CodingUserInfoKey: Any]?) throws {
            let expectedElements = 1

            guard jsonList.count == expectedElements else {
                throw JSONListConvertibleError.unexpectedNumberOfItems(
                    expected: expectedElements,
                    actual: jsonList.count
                )
            }

            index = try jsonList[0].map(to: StringScaleMapper<FamilyIndex>.self, with: context).value
        }
    }

    typealias DesignFamiliesResult = [DesignFamiliesKey: Family]
    typealias ReservedDesignsResult = [FamilyIndex: Set<DesignIndex>]

    struct CommittedDesignKey: Equatable, Hashable, JSONListConvertible {
        public let familyIndex: FamilyIndex
        public let designIndex: DesignIndex

        public init(familyIndex: FamilyIndex, designIndex: DesignIndex) {
            self.familyIndex = familyIndex
            self.designIndex = designIndex
        }

        public init(jsonList: [JSON], context: [CodingUserInfoKey: Any]?) throws {
            guard jsonList.count == 2 else {
                throw JSONListConvertibleError.unexpectedNumberOfItems(
                    expected: 2,
                    actual: jsonList.count
                )
            }

            familyIndex = try jsonList[0].map(
                to: StringScaleMapper.self,
                with: context
            ).value

            designIndex = try jsonList[1].map(
                to: StringScaleMapper.self,
                with: context
            ).value
        }
    }
}

public extension ProofOfInkPallet.FamilyKind.Designed {
    func fetchFirst(
        numberOfItems: Int,
        reserved: Set<ProofOfInkPallet.DesignIndex>
    ) -> [ProofOfInkPallet.DesignIndex] {
        var items: [ProofOfInkPallet.DesignIndex] = []
        var currentIndex: ProofOfInkPallet.DesignIndex = 0

        while currentIndex < count {
            if !reserved.contains(currentIndex) {
                items.append(currentIndex)
            }

            currentIndex += 1

            if items.count >= numberOfItems {
                break
            }
        }

        return items
    }
}
