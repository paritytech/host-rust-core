import Foundation
import Operation_iOS
import SubstrateSdk
import ExtrinsicService

public final class AsPersonalIdentityOrigin {
    let model: PeoplePallet.AsPersonTxExtension.AsPersonalIdentityWithProofUsability

    public init(model: PeoplePallet.AsPersonTxExtension.AsPersonalIdentityWithProofUsability) {
        self.model = model
    }
}

private extension AsPersonalIdentityOrigin {
    func createExtensionAppendingOperation(
        for model: PeoplePallet.AsPersonTxExtension.AsPersonalIdentityWithProofUsability,
        dependency: @escaping () throws -> ExtrinsicOriginDefinitionDependency,
        extrinsicVersion: Extrinsic.Version
    ) -> BaseOperation<ExtrinsicOriginDefinitionResponse> {
        ClosureOperation {
            let dependencies = try dependency()

            let txExtension = PeoplePallet.AsPersonTxExtension(
                extrinsicVersion: extrinsicVersion,
                usability: .asPersonalIdentityWithProof(model)
            )

            let builders = dependencies.builders.map { builder in
                builder.adding(transactionExtension: txExtension)
            }

            return ExtrinsicOriginDefinitionResponse(
                builders: builders,
                senderResolution: dependencies.senderResolution,
                feePayment: dependencies.feePayment
            )
        }
    }
}

extension AsPersonalIdentityOrigin: ExtrinsicOriginDefining {
    public func createOriginResolutionWrapper(
        for dependency: @escaping () throws -> ExtrinsicOriginDefinitionDependency,
        extrinsicVersion: Extrinsic.Version,
        purpose _: ExtrinsicOriginPurpose
    ) -> CompoundOperationWrapper<ExtrinsicOriginDefinitionResponse> {
        let operation = createExtensionAppendingOperation(
            for: model,
            dependency: dependency,
            extrinsicVersion: extrinsicVersion
        )

        return CompoundOperationWrapper(targetOperation: operation)
    }
}
