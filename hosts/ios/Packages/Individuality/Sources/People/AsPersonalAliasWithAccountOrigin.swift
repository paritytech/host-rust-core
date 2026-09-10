import Foundation
import Operation_iOS
import SubstrateSdk
import ExtrinsicService
import KeyDerivation
import StructuredConcurrency

public final class AsPersonalAliasWithAccountDefinition {
    private let input: AsPersonAliasWithAccountInput
    private let aliasRevisionFactory: AliasRevisionOperationMaking
    private let proofParamsFetcher: MembershipProofParamsFetching
    private let vrfManager: BandersnatchKeyManaging
    private let operationQueue: OperationQueue

    public init(
        input: AsPersonAliasWithAccountInput,
        aliasRevisionFactory: AliasRevisionOperationMaking,
        proofParamsFetcher: MembershipProofParamsFetching,
        vrfManager: BandersnatchKeyManaging,
        operationQueue: OperationQueue
    ) {
        self.input = input
        self.aliasRevisionFactory = aliasRevisionFactory
        self.proofParamsFetcher = proofParamsFetcher
        self.vrfManager = vrfManager
        self.operationQueue = operationQueue
    }
}

extension AsPersonalAliasWithAccountDefinition: ExtrinsicOriginDefining {
    enum ResolutionError: Error {
        case missingNonce
        case missingAccoundId
        case emptyRingKeys
        case memberNotIncluded
    }

    public func createOriginResolutionWrapper(
        for dependency: @escaping () throws -> ExtrinsicOriginDefinitionDependency,
        extrinsicVersion: Extrinsic.Version,
        purpose _: ExtrinsicOriginPurpose
    ) -> CompoundOperationWrapper<ExtrinsicOriginDefinitionResponse> {
        let aliasRevisionWrapper = aliasRevisionWrapper(dependency: dependency)

        let resultWrapper: CompoundOperationWrapper<
            ExtrinsicOriginDefinitionResponse
        > = OperationCombiningService.compoundNonOptionalWrapper(
            operationManager: OperationManager(operationQueue: operationQueue)
        ) { [weak self] in
            guard let self else {
                throw BaseOperationError.unexpectedDependentResult
            }

            let revisionResult = try aliasRevisionWrapper.targetOperation
                .extractNoCancellableResultData()

            if revisionResult.isUpToDate {
                return plainResolutionWrapper(
                    dependency: dependency,
                    extrinsicVersion: extrinsicVersion
                )
            } else {
                return revisedResolutionWrapper(
                    collectionId: PeoplePallet.membersIdentifier,
                    ringIndex: revisionResult.ring,
                    dependency: dependency,
                    extrinsicVersion: extrinsicVersion
                )
            }
        }
        resultWrapper.addDependency(wrapper: aliasRevisionWrapper)

        return resultWrapper.insertingHead(operations: aliasRevisionWrapper.allOperations)
    }
}

private extension AsPersonalAliasWithAccountDefinition {
    func aliasRevisionWrapper(
        dependency: @escaping () throws -> ExtrinsicOriginDefinitionDependency,
    ) -> CompoundOperationWrapper<AliasRevisionResult> {
        aliasRevisionFactory.checkAliasRevision(
            accountIdClosure: {
                guard let accountId = try dependency().senderResolution.account?.accountId else {
                    throw ResolutionError.missingAccoundId
                }
                return accountId
            },
            blockHash: input.blockHash
        )
    }

    func plainResolutionWrapper(
        dependency: @escaping () throws -> ExtrinsicOriginDefinitionDependency,
        extrinsicVersion: Extrinsic.Version,
    ) -> CompoundOperationWrapper<ExtrinsicOriginDefinitionResponse> {
        CompoundOperationWrapper(targetOperation: plainDefinitionResponseOperation(
            dependency: dependency,
            extrinsicVersion: extrinsicVersion
        ))
    }

    func plainDefinitionResponseOperation(
        dependency: @escaping () throws -> ExtrinsicOriginDefinitionDependency,
        extrinsicVersion: Extrinsic.Version
    ) -> BaseOperation<ExtrinsicOriginDefinitionResponse> {
        ClosureOperation {
            let dependencies = try dependency()

            let builders = try dependencies.builders.map { builder in
                guard let nonce = builder.getNonce() else {
                    throw ResolutionError.missingNonce
                }

                let txExtension = PeoplePallet.AsPersonTxExtension(
                    extrinsicVersion: extrinsicVersion,
                    usability: .asPersonalAliasWithAccount(nonce)
                )

                return builder.adding(transactionExtension: txExtension)
            }

            return ExtrinsicOriginDefinitionResponse(
                builders: builders,
                senderResolution: dependencies.senderResolution,
                feePayment: dependencies.feePayment
            )
        }
    }

    func revisedResolutionWrapper(
        collectionId: MembersPallet.CollectionIdentifier,
        ringIndex: MembersPallet.RingIndex,
        dependency: @escaping () throws -> ExtrinsicOriginDefinitionDependency,
        extrinsicVersion: Extrinsic.Version
    ) -> CompoundOperationWrapper<ExtrinsicOriginDefinitionResponse> {
        let proofParamsOperation = AsyncTaskOperation { [proofParamsFetcher, input] in
            try await proofParamsFetcher.fetchOrError(
                for: ringIndex,
                collectionId: collectionId,
                blockHash: input.blockHash
            )
        }

        let definitionResponseOperation = revisedDefinitionResponseOperation(
            ringIndex: ringIndex,
            proofParamsOperation: proofParamsOperation,
            dependency: dependency,
            extrinsicVersion: extrinsicVersion
        )
        definitionResponseOperation.addDependency(proofParamsOperation)

        return CompoundOperationWrapper(
            targetOperation: definitionResponseOperation,
            dependencies: [proofParamsOperation]
        )
    }

    func revisedDefinitionResponseOperation(
        ringIndex: MembersPallet.RingIndex,
        proofParamsOperation: BaseOperation<MembersProofParams>,
        dependency: @escaping () throws -> ExtrinsicOriginDefinitionDependency,
        extrinsicVersion: Extrinsic.Version
    ) -> BaseOperation<ExtrinsicOriginDefinitionResponse> {
        ClosureOperation { [weak self] in
            guard let self else {
                throw BaseOperationError.unexpectedDependentResult
            }

            let proofParams = try proofParamsOperation.extractNoCancellableResultData()

            let memberKey = try vrfManager.getMemberKey()
            guard proofParams.ringMembers.contains(memberKey) else {
                throw ResolutionError.memberNotIncluded
            }

            return try makeRevisedDefinitionResponse(
                proofParams: proofParams,
                ringIndex: ringIndex,
                dependency: dependency,
                extrinsicVersion: extrinsicVersion
            )
        }
    }

    func makeRevisedDefinitionResponse(
        proofParams: MembersProofParams,
        ringIndex: MembersPallet.RingIndex,
        dependency: @escaping () throws -> ExtrinsicOriginDefinitionDependency,
        extrinsicVersion: Extrinsic.Version
    ) throws -> ExtrinsicOriginDefinitionResponse {
        let dependencies = try dependency()

        guard let accountId = dependencies.senderResolution.account?.accountId else {
            throw ResolutionError.missingAccoundId
        }

        let builders = try dependencies.builders.map { [weak self] builder in
            guard let self else {
                throw BaseOperationError.unexpectedDependentResult
            }

            guard let nonce = builder.getNonce() else {
                throw ResolutionError.missingNonce
            }

            let txExtension = PeoplePallet.AsPersonTxExtension(
                extrinsicVersion: extrinsicVersion,
                usability: .asPersonalAliasWithAccountRevised(.init(
                    nonce: nonce,
                    accountId: accountId,
                    vrfManager: vrfManager,
                    ringIndex: ringIndex,
                    proofParams: proofParams,
                    context: input.context
                ))
            )

            return builder.adding(transactionExtension: txExtension)
        }

        return ExtrinsicOriginDefinitionResponse(
            builders: builders,
            senderResolution: dependencies.senderResolution,
            feePayment: dependencies.feePayment
        )
    }
}

public struct AsPersonAliasWithAccountInput {
    public let wallet: WalletManaging
    public let chain: ChainProtocol
    public let context: Data
    public let blockHash: Data?

    public init(wallet: WalletManaging, chain: ChainProtocol, context: Data, blockHash: Data?) {
        self.wallet = wallet
        self.chain = chain
        self.context = context
        self.blockHash = blockHash
    }
}
