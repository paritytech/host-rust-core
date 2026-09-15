import Foundation
import SubstrateSdk
import NovaCrypto
import Operation_iOS

protocol VoucherAllocating: Actor {
    func allocate(exponent: Int16) async throws -> Voucher
}

/// Actor isolation serialises the index counter's read-modify-write, so a single shared instance is
/// the only safe configuration — do not create more than one against the same index store.
actor VoucherAllocator: VoucherAllocating {
    private let storage: CoinageIndexstoreProtocol
    private let delayProvider: VoucherDelayProviderProtocol
    private let voucherRepository: AnyDataProviderRepository<Voucher>
    private let keyFactory: any VoucherKeyDeriving

    init(
        storage: CoinageIndexstoreProtocol,
        delayProvider: VoucherDelayProviderProtocol,
        voucherRepository: AnyDataProviderRepository<Voucher>,
        keyFactory: any VoucherKeyDeriving
    ) {
        self.storage = storage
        self.delayProvider = delayProvider
        self.voucherRepository = voucherRepository
        self.keyFactory = keyFactory
    }

    /// Allocates a new voucher index and persists the voucher — with its on-chain public key cached
    /// so the durability layer never re-derives it — from the moment it is minted.
    func allocate(exponent: Int16) async throws -> Voucher {
        let index = try storage.getNextIndex()
        let delay = delayProvider.timeInterval()
        let allocatedAt = Date.now

        let voucher = try Voucher(
            exponent: exponent,
            derivationIndex: index,
            allocatedAt: allocatedAt,
            readyAt: allocatedAt.addingTimeInterval(delay),
            publicKey: keyFactory.derivePublicKey(index: index)
        )
        try await voucherRepository.saveOperation({ [voucher] }, { [] }).asyncExecute()
        return voucher
    }
}

protocol VoucherDelayProviderProtocol {
    func timeInterval() -> TimeInterval
}

final class VoucherDelayProvider: VoucherDelayProviderProtocol {
    private let maxWaitTime: TimeInterval = CoinageConstants.maxVoucherWaitTime

    func timeInterval() -> TimeInterval {
        TimeInterval.random(in: 0 ... maxWaitTime)
    }
}
