import Foundation
import Operation_iOS
import SubstrateSdk
import ExtrinsicService

enum AsParticipantOriginDefinitionError: Error {
    case missingNonce
}

public final class AsParticipantOriginDefinition {
    let mode: Mode

    public init(mode: Mode) {
        self.mode = mode
    }
}

public extension AsParticipantOriginDefinition {
    enum Mode {
        case applyWithSig
        case asReferred
        case asInvited
    }
}

private extension AsParticipantOriginDefinition {
    func createExtension(for nonce: AccountNonce) -> TransactionExtending {
        switch mode {
        case .applyWithSig:
            ProofOfInk.AsParticipantExtension(mode: .applyWithSig(nonce))
        case .asReferred:
            ProofOfInk.AsParticipantExtension(mode: .asReferred(nonce))
        case .asInvited:
            ProofOfInk.AsParticipantExtension(mode: .asInvited(nonce))
        }
    }
}

extension AsParticipantOriginDefinition: ExtrinsicOriginDefining {
    public func createOriginResolutionWrapper(
        for dependency: @escaping () throws -> ExtrinsicOriginDefinitionDependency,
        extrinsicVersion _: Extrinsic.Version,
        purpose _: ExtrinsicOriginPurpose
    ) -> CompoundOperationWrapper<ExtrinsicOriginDefinitionResponse> {
        let operation = ClosureOperation<ExtrinsicOriginDefinitionResponse> {
            let dependencies = try dependency()

            let builders = try dependencies.builders.map { builder in
                guard let nonce = builder.getNonce() else {
                    throw AsParticipantOriginDefinitionError.missingNonce
                }

                let txExtension = self.createExtension(for: nonce)

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
