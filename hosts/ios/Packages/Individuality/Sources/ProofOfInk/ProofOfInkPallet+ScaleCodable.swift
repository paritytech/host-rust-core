import Foundation
import SubstrateSdk

extension ProofOfInkPallet.InkSpec: ScaleCodable {
    public init(scaleDecoder: any ScaleDecoding) throws {
        let type = try UInt8(scaleDecoder: scaleDecoder)
        switch type {
        case 0:
            let familyIndex = try ProofOfInkPallet.FamilyIndex(scaleDecoder: scaleDecoder)
            let design = try ProofOfInkPallet.DesignIndex(scaleDecoder: scaleDecoder)
            self = .designedElective(.init(familyIndex: familyIndex, design: design))
        case 1:
            let familyIndex = try ProofOfInkPallet.FamilyIndex(scaleDecoder: scaleDecoder)
            let accountId = try AccountId(scaleDecoder: scaleDecoder)
            self = .proceduralAccount(.init(familyIndex: familyIndex, accountId: accountId))
        case 2:
            let familyIndex = try ProofOfInkPallet.FamilyIndex(scaleDecoder: scaleDecoder)
            let personalId = try ProofOfInkPallet.PersonalId(scaleDecoder: scaleDecoder)
            self = .proceduralPersonal(.init(familyIndex: familyIndex, personalId: personalId))
        case 3:
            let familyIndex = try ProofOfInkPallet.FamilyIndex(scaleDecoder: scaleDecoder)
            let proceduralSeed = try ProofOfInkPallet.ProceduralSeed(scaleDecoder: scaleDecoder)
            self = .procedural(.init(familyIndex: familyIndex, proceduralSeed: proceduralSeed))
        default:
            throw ScaleDecoderError.outOfBounds
        }
    }

    public func encode(scaleEncoder: any ScaleEncoding) throws {
        switch self {
        case let .designedElective(designed):
            let type: UInt8 = 0
            try type.encode(scaleEncoder: scaleEncoder)
            try designed.familyIndex.encode(scaleEncoder: scaleEncoder)
            try designed.design.encode(scaleEncoder: scaleEncoder)
        case let .proceduralAccount(proceduralAccount):
            let type: UInt8 = 1
            try type.encode(scaleEncoder: scaleEncoder)
            try proceduralAccount.familyIndex.encode(scaleEncoder: scaleEncoder)
            try proceduralAccount.accountId.encode(scaleEncoder: scaleEncoder)
        case let .proceduralPersonal(proceduralPersonal):
            let type: UInt8 = 2
            try type.encode(scaleEncoder: scaleEncoder)
            try proceduralPersonal.familyIndex.encode(scaleEncoder: scaleEncoder)
            try proceduralPersonal.personalId.encode(scaleEncoder: scaleEncoder)
        case let .procedural(procedural):
            let type: UInt8 = 3
            try type.encode(scaleEncoder: scaleEncoder)
            try procedural.familyIndex.encode(scaleEncoder: scaleEncoder)
            try procedural.proceduralSeed.encode(scaleEncoder: scaleEncoder)
        }
    }
}
