import SubstrateSdk
import Operation_iOS
import NovaCrypto
import Keystore_iOS
import ExtrinsicService

enum ScoreAsParticipantOriginDefinitionError: Error {
    case missingNonce
}

public final class ScoreAsParticipantOriginDefinition {
    public init() {}
}

private extension ScoreAsParticipantOriginDefinition {
    func createExtension(for nonce: AccountNonce) throws -> TransactionExtending {
        ScorePallet.ScoreAsParticipantExtension(nonce: nonce)
    }
}

extension ScoreAsParticipantOriginDefinition: ExtrinsicOriginDefining {
    public func createOriginResolutionWrapper(
        for dependency: @escaping () throws -> ExtrinsicOriginDefinitionDependency,
        extrinsicVersion _: Extrinsic.Version,
        purpose _: ExtrinsicOriginPurpose
    ) -> CompoundOperationWrapper<ExtrinsicOriginDefinitionResponse> {
        let operation = ClosureOperation<ExtrinsicOriginDefinitionResponse> {
            let dependencies = try dependency()

            let builders = try dependencies.builders.map { builder in
                guard let nonce = builder.getNonce() else {
                    throw ScoreAsParticipantOriginDefinitionError.missingNonce
                }

                let txExtension = try self.createExtension(for: nonce)

                return builder.adding(transactionExtension: txExtension)
            }

            return ExtrinsicOriginDefinitionResponse(
                builders: builders,
                senderResolution: dependencies.senderResolution,
                feePayment: dependencies.feePayment
            )
        }

        return CompoundOperationWrapper(targetOperation: operation)
    }
}
