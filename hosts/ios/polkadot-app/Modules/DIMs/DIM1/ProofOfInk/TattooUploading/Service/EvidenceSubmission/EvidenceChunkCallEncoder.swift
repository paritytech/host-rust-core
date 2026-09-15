import BulletinChain
import Foundation
import SubstrateSdk

enum EvidenceChunkCallEncoderError: Error {
    case callMissing
}

final class EvidenceChunkCallEncoder {
    func encode(
        call: TransactionStoragePallet.StoreCall,
        codingFactory: RuntimeCoderFactoryProtocol
    ) throws -> Data {
        let runtimeCall = call.runtimeCall()
        let runtimeMetadata = codingFactory.metadata

        guard
            let moduleIndex = runtimeMetadata.getModuleIndex(runtimeCall.moduleName),
            let callIndex = runtimeMetadata.getCallIndex(
                in: runtimeCall.moduleName,
                callName: runtimeCall.callName
            ) else {
            throw EvidenceChunkCallEncoderError.callMissing
        }

        let encoder = codingFactory.createEncoder()

        try encoder.appendU8(json: .stringValue(String(moduleIndex)))
        try encoder.appendU8(json: .stringValue(String(callIndex)))

        try encoder.appendCompact(
            json: .stringValue(String(call.data.count)),
            type: PrimitiveType.u128.name
        )

        let header = try encoder.encode()

        return header + call.data
    }
}
