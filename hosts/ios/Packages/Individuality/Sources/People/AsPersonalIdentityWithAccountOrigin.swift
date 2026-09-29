import Foundation
import Operation_iOS
import SubstrateSdk
import ExtrinsicService

public final class AsPersonalIdentityWithAccountOrigin {
    public init() {}
}

extension AsPersonalIdentityWithAccountOrigin: ExtrinsicOriginDefining {
    enum ResolutionError: Error {
        case missingNonce
    }

    public func createOriginResolutionWrapper(
        for dependency: @escaping () throws -> ExtrinsicOriginDefinitionDependency,
        extrinsicVersion: Extrinsic.Version,
        purpose _: ExtrinsicOriginPurpose
    ) -> CompoundOperationWrapper<ExtrinsicOriginDefinitionResponse> {
        let operation = ClosureOperation<ExtrinsicOriginDefinitionResponse> {
            let dependencies = try dependency()

            let builders = try dependencies.builders.map { builder in
                guard let nonce = builder.getNonce() else {
                    throw ResolutionError.missingNonce
                }

                let txExtension = PeoplePallet.AsPersonTxExtension(
                    extrinsicVersion: extrinsicVersion,
                    usability: .asPersonalIdentityWithAccount(nonce)
                )

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
