import Foundation
import BandersnatchApi
import SubstrateSdk
import ExtrinsicService
import StructuredConcurrency
import BigInt
import KeyDerivation
import Keystore_iOS
import SDKLogger
import Operation_iOS

public protocol VoucherServiceProtocol: Sendable {
    /// Loads vouchers for `amount` and returns them.
    @discardableResult
    func load(
        amount: BigUInt,
        externalAssetHolder: any WalletManaging,
        breakdownContext: DenominationBreakdownContext
    ) async throws -> [Voucher]

    /// Fetch all vouchers paired with their derived durability overlay.
    func fetchAllTracked() async throws -> [TrackedVoucher]
}

public final class VoucherService: @unchecked Sendable {
    private let trackedVoucherRepository: AnyDataProviderRepository<TrackedVoucher>
    private let voucherLoaderFactory: VoucherLoaderFactoryProtocol

    public init(
        trackedVoucherRepository: AnyDataProviderRepository<TrackedVoucher>,
        voucherLoaderFactory: VoucherLoaderFactoryProtocol
    ) {
        self.trackedVoucherRepository = trackedVoucherRepository
        self.voucherLoaderFactory = voucherLoaderFactory
    }
}

extension VoucherService: VoucherServiceProtocol {
    @discardableResult
    public func load(
        amount: BigUInt,
        externalAssetHolder: any WalletManaging,
        breakdownContext: DenominationBreakdownContext
    ) async throws -> [Voucher] {
        let loader = try voucherLoaderFactory.makeLoader(for: externalAssetHolder)
        // Vouchers are persisted by the allocator as they are minted.
        return try await loader.load(amount: amount, breakdownContext: breakdownContext)
    }

    public func fetchAllTracked() async throws -> [TrackedVoucher] {
        try await trackedVoucherRepository.fetchAllOperation(with: RepositoryFetchOptions()).asyncExecute()
    }
}
