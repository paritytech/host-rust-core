import Foundation
import Operation_iOS
import SubstrateSdk
import BandersnatchApi
import ExtrinsicService
import Foundation_iOS
import KeyDerivation
import ChainRegistry

protocol ClaimRewardsServicing {
    func claimVouchers(
        _ vouchers: [RemotePrivacyVoucher],
        into destination: AccountId
    ) -> CompoundOperationWrapper<ClaimRewardsResult>
}

struct ClaimRewardsResult: CustomStringConvertible {
    let claimedVouchersByIdentifier: [String: RemotePrivacyVoucher]
    let errors: [Error]

    var description: String {
        let claimed = "Claimed count: \(claimedVouchersByIdentifier.count)"
        let errors = "Errors: \(errors.map(\.localizedDescription))"
        return "\(claimed); \(errors)"
    }

    static var empty: ClaimRewardsResult {
        .init(claimedVouchersByIdentifier: [:], errors: [])
    }
}

final class ClaimRewardsService: ClaimRewardsServicing {
    private let chain: ChainModel
    private let payoutAccount: WalletManaging
    private let connection: JSONRPCEngine
    private let runtimeProvider: RuntimeProviderProtocol
    private let extrinsicMonitor: ExtrinsicSubmitMonitorFactoryProtocol
    private let originFactory: ExtrinsicOriginDefiningFactoryProtocol
    private let privacyVoucherOperationFactory: PrivacyVoucherOperationMaking
    private let operationQueue: OperationQueue

    private var memberKeys = InMemoryCache<PrivacyVoucherPallet.KeysToRing, [PrivacyVoucherPallet.MemberKey]>()

    init(
        chain: ChainModel,
        connection: JSONRPCEngine,
        runtimeProvider: RuntimeProviderProtocol,
        extrinsicMonitor: ExtrinsicSubmitMonitorFactoryProtocol,
        originFactory: ExtrinsicOriginDefiningFactoryProtocol,
        payoutAccount: WalletManaging = WalletManagerRepository.shared.internalPayout(),
        privacyVoucherOperationFactory: PrivacyVoucherOperationMaking = PrivacyVoucherOperationFactory(),
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue
    ) {
        self.chain = chain
        self.connection = connection
        self.runtimeProvider = runtimeProvider
        self.extrinsicMonitor = extrinsicMonitor
        self.originFactory = originFactory
        self.payoutAccount = payoutAccount
        self.privacyVoucherOperationFactory = privacyVoucherOperationFactory
        self.operationQueue = operationQueue
    }

    func claimVouchers(
        _ vouchers: [RemotePrivacyVoucher],
        into destination: AccountId
    ) -> CompoundOperationWrapper<ClaimRewardsResult> {
        let wrappers = vouchers.map { voucher in
            let memberKeysWrapper = fetchMemberKeys(for: .init(
                balanceOf: voucher.balanceOf,
                ringIndex: voucher.ringIndex
            ))

            let proofOperation = generateProof(
                for: voucher,
                with: memberKeysWrapper
            )

            let claimWrapper = claimVoucher(
                voucher,
                into: destination,
                proofOperation: proofOperation
            )

            let resultOperation = resultOperation(
                for: voucher,
                claimWrapper: claimWrapper
            )

            return CompoundOperationWrapper(
                targetOperation: resultOperation,
                dependencies: memberKeysWrapper.allOperations
                    + [proofOperation]
                    + claimWrapper.allOperations
            )
        }

        wrappers.enumerated().forEach { index, wrapper in
            if index > 0 {
                wrapper.addDependency(wrapper: wrappers[index - 1])
            }
        }

        let mapResultOperation = ClosureOperation {
            var claimedVouchersByIdentifier = [String: RemotePrivacyVoucher]()
            var errors = [Error]()

            for wrapper in wrappers {
                do {
                    let result = try wrapper.targetOperation.extractNoCancellableResultData()
                    claimedVouchersByIdentifier[result.localData.identifier] = result
                } catch {
                    errors.append(error)
                }
            }

            return ClaimRewardsResult(
                claimedVouchersByIdentifier: claimedVouchersByIdentifier,
                errors: errors
            )
        }

        if let lastWrapper = wrappers.last {
            mapResultOperation.addDependency(lastWrapper.targetOperation)
        }

        return .init(
            targetOperation: mapResultOperation,
            dependencies: wrappers.flatMap(\.allOperations)
        )
    }
}

private extension ClaimRewardsService {
    func fetchMemberKeys(
        for keysToRing: PrivacyVoucherPallet.KeysToRing
    ) -> CompoundOperationWrapper<[PrivacyVoucherPallet.MemberKey]> {
        if let memberKeys = memberKeys.fetchValue(for: keysToRing) {
            return .createWithResult(memberKeys)
        }

        let fetchWrapper = privacyVoucherOperationFactory.fetchKeys(
            for: keysToRing,
            connection: connection,
            runtimeProvider: runtimeProvider
        )

        let cacheOperation = ClosureOperation { [weak self] in
            let memberKeys = try fetchWrapper.targetOperation.extractNoCancellableResultData()
            self?.memberKeys.store(value: memberKeys, for: keysToRing)
            return memberKeys
        }
        cacheOperation.addDependency(fetchWrapper.targetOperation)

        return .init(
            targetOperation: cacheOperation,
            dependencies: fetchWrapper.allOperations
        )
    }

    func generateProof(
        for voucher: RemotePrivacyVoucher,
        with memberKeysWrapper: CompoundOperationWrapper<[PrivacyVoucherPallet.MemberKey]>
    ) -> BaseOperation<Data> {
        let result = ClosureOperation { [payoutAccount, chain] in
            guard let message = try? payoutAccount.fetchAccount(for: chain).accountId else {
                throw BaseOperationError.unexpectedDependentResult
            }
            return try BandersnatchApi.createProof(
                from: voucher.localData.key.entropy,
                members: memberKeysWrapper.targetOperation.extractNoCancellableResultData(),
                message: message,
                context: Data(PrivacyVoucherPallet.context.utf8),
                domainSize: .domain11
            )
        }

        result.addDependency(memberKeysWrapper.targetOperation)

        return result
    }

    func claimVoucher(
        _ voucher: RemotePrivacyVoucher,
        into destination: AccountId,
        proofOperation: BaseOperation<Data>
    ) -> CompoundOperationWrapper<ExtrinsicMonitorSubmission> {
        let result: CompoundOperationWrapper<ExtrinsicMonitorSubmission>

        do {
            let origin = try originFactory.extrinsicOriginDefiner(from: payoutAccount, chain: chain)

            result = extrinsicMonitor.submitAndMonitorWrapper(
                extrinsicBuilderClosure: { builder in
                    let proof = try proofOperation.extractNoCancellableResultData()

                    let call = PrivacyVoucherPallet.ClaimVoucherCall(
                        proof: proof,
                        dest: destination,
                        voucherValue: voucher.balanceOf,
                        ringIndex: voucher.ringIndex
                    )

                    return try builder.adding(call: call.runtimeCall())
                },
                origin: origin,
                params: .init(feeAssetId: nil, eventsMatcher: nil)
            )
        } catch {
            result = .createWithError(error)
        }

        result.addDependency(operations: [proofOperation])

        return result
    }

    func resultOperation(
        for voucher: RemotePrivacyVoucher,
        claimWrapper: CompoundOperationWrapper<ExtrinsicMonitorSubmission>
    ) -> BaseOperation<RemotePrivacyVoucher> {
        let operation = ClosureOperation {
            let status = try claimWrapper.targetOperation.extractNoCancellableResultData()

            switch status.status {
            case .success:
                return voucher
            case let .failure(dispatchExtrinsicError):
                throw dispatchExtrinsicError.error
            }
        }

        operation.addDependency(claimWrapper.targetOperation)

        return operation
    }
}
