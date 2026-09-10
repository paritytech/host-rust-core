import Foundation
import SubstrateSdk
import ExtrinsicService
import Operation_iOS
import KeyDerivation

public final class AsMemberOriginDefinition: ExtrinsicOriginDefining {
    private let vrfManager: BandersnatchKeyManaging

    public init(vrfManager: BandersnatchKeyManaging) {
        self.vrfManager = vrfManager
    }

    public func createOriginResolutionWrapper(
        for dependency: @escaping () throws -> ExtrinsicOriginDefinitionDependency,
        extrinsicVersion: Extrinsic.Version,
        purpose _: ExtrinsicOriginPurpose
    ) -> CompoundOperationWrapper<ExtrinsicOriginDefinitionResponse> {
        let resultOperation = ClosureOperation<ExtrinsicOriginDefinitionResponse> { [vrfManager] in
            let deps = try dependency()

            let txExtension = MembersPallet.AsMemberTxExtension(
                extrinsicVersion: extrinsicVersion,
                vrfManager: vrfManager
            )

            let builders = deps.builders.map { builder in
                builder.adding(transactionExtension: txExtension)
            }

            return ExtrinsicOriginDefinitionResponse(
                builders: builders,
                senderResolution: deps.senderResolution,
                feePayment: deps.feePayment
            )
        }

        return CompoundOperationWrapper(targetOperation: resultOperation)
    }
}
