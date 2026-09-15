import SubstrateSdk
import Operation_iOS
import ExtrinsicService
import SubstrateSdkExt

enum AsGameInvitedOriginDefinitionError: Error {
    case missingNonce
}

public final class AsGameInvitedOriginDefinition {
    let inviter: AccountId
    let ticket: AccountId
    let signature: MultiSignature

    public init(inviter: AccountId, ticket: AccountId, signature: MultiSignature) {
        self.inviter = inviter
        self.ticket = ticket
        self.signature = signature
    }
}

private extension AsGameInvitedOriginDefinition {
    func createExtension(for nonce: AccountNonce) -> TransactionExtending {
        GamePallet.GameAsInvitedExtension(
            nonce: nonce,
            inviter: inviter,
            ticket: ticket,
            signature: signature
        )
    }
}

extension AsGameInvitedOriginDefinition: ExtrinsicOriginDefining {
    public func createOriginResolutionWrapper(
        for dependency: @escaping () throws -> ExtrinsicOriginDefinitionDependency,
        extrinsicVersion _: Extrinsic.Version,
        purpose _: ExtrinsicOriginPurpose
    ) -> CompoundOperationWrapper<ExtrinsicOriginDefinitionResponse> {
        let operation = ClosureOperation<ExtrinsicOriginDefinitionResponse> {
            let dependencies = try dependency()

            let builders = try dependencies.builders.map { builder in
                guard let nonce = builder.getNonce() else {
                    throw AsGameInvitedOriginDefinitionError.missingNonce
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
