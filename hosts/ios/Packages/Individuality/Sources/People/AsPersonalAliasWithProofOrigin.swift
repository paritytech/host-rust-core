import Foundation
import ExtrinsicService
import SubstrateSdk
import Operation_iOS
import KeyDerivation
import StructuredConcurrency
import ChainStore

public final class AsPersonalAliasWithProofOrigin {
    let input: AsPersonAliasWithProofInput
    let proofParamsFetcher: MembershipProofParamsFetching
    let vrfManager: BandersnatchKeyManaging
    let operationQueue: OperationQueue

    public init(
        input: AsPersonAliasWithProofInput,
        proofParamsFetcher: MembershipProofParamsFetching,
        vrfManager: BandersnatchKeyManaging,
        operationQueue: OperationQueue
    ) {
        self.input = input
        self.proofParamsFetcher = proofParamsFetcher
        self.vrfManager = vrfManager
        self.operationQueue = operationQueue
    }
}

private extension AsPersonalAliasWithProofOrigin {
    func createExtensionAppendingOperation(
        for model: PeoplePallet.AsPersonTxExtension.AsPersonalAliasWithProofUsability,
        dependency: @escaping () throws -> ExtrinsicOriginDefinitionDependency,
        extrinsicVersion: Extrinsic.Version
    ) -> BaseOperation<ExtrinsicOriginDefinitionResponse> {
        ClosureOperation {
            let dependencies = try dependency()

            let txExtension = PeoplePallet.AsPersonTxExtension(
                extrinsicVersion: extrinsicVersion,
                usability: .asPersonalAliasWithProof(model)
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

extension AsPersonalAliasWithProofOrigin: ExtrinsicOriginDefining {
    enum ProofError: Error {
        case noProofParams
        case memberNotIncluded
    }

    public func createOriginResolutionWrapper(
        for dependency: @escaping () throws -> ExtrinsicOriginDefinitionDependency,
        extrinsicVersion: Extrinsic.Version,
        purpose _: ExtrinsicOriginPurpose
    ) -> CompoundOperationWrapper<ExtrinsicOriginDefinitionResponse> {
        let proofParamOperation = AsyncTaskOperation { [proofParamsFetcher, input] in
            try await proofParamsFetcher.fetch(
                for: input.ringIndex,
                collectionId: input.collectionId,
                blockHash: input.blockHash
            )
        }

        let resultWrapper: CompoundOperationWrapper<ExtrinsicOriginDefinitionResponse>
        resultWrapper = OperationCombiningService.compoundNonOptionalWrapper(
            operationManager: OperationManager(operationQueue: operationQueue)
        ) { [weak self] in
            guard let self else {
                throw BaseOperationError.unexpectedDependentResult
            }

            guard let proofParams = try proofParamOperation.extractNoCancellableResultData() else {
                return .createWithError(ProofError.noProofParams)
            }

            let memberKey = try vrfManager.getMemberKey()

            guard proofParams.ringMembers.contains(memberKey) else {
                return .createWithError(ProofError.memberNotIncluded)
            }

            let operation = createExtensionAppendingOperation(
                for: .init(
                    vrfManager: vrfManager,
                    ringIndex: input.ringIndex,
                    proofParams: proofParams,
                    context: input.context
                ),
                dependency: dependency,
                extrinsicVersion: extrinsicVersion
            )
            return CompoundOperationWrapper(targetOperation: operation)
        }

        resultWrapper.addDependency(operations: [proofParamOperation])

        return resultWrapper.insertingHead(operations: [proofParamOperation])
    }
}

public struct AsPersonAliasWithProofInput {
    let collectionId: MembersPallet.CollectionIdentifier
    let ringIndex: MembersPallet.RingIndex
    let context: Data
    let blockHash: Data?

    public init(
        collectionId: MembersPallet.CollectionIdentifier,
        ringIndex: MembersPallet.RingIndex,
        context: Data,
        blockHash: Data?
    ) {
        self.collectionId = collectionId
        self.ringIndex = ringIndex
        self.context = context
        self.blockHash = blockHash
    }
}
