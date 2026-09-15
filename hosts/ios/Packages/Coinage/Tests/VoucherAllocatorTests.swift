import Testing
import Foundation
import SubstrateSdk
import NovaCrypto
import Keystore_iOS
import Operation_iOS
@testable import Coinage

struct VoucherAllocatorTests {
    private let keychain: InMemoryKeychain
    private let store: VoucherIndexstore
    private let mockDelay: MockDelayProvider
    private let allocator: VoucherAllocator

    init() {
        keychain = InMemoryKeychain()
        store = VoucherIndexstore(storage: keychain)
        mockDelay = MockDelayProvider()
        allocator = VoucherAllocator(
            storage: store,
            delayProvider: mockDelay,
            voucherRepository: AnyDataProviderRepository(StubRepository<Voucher>()),
            keyFactory: VoucherKeypairFactory(entropyManager: MockEntropyManager(entropy: Data(
                repeating: 0x01,
                count: 32
            )))
        )
    }

    @Test("Successfully allocates a voucher")
    func allocateVoucher() async throws {
        let expectedIndex: UInt64 = 7
        let expectedDelay: TimeInterval = 3_600

        try keychain.saveKey(UInt64(6).scaleEncoded(), with: store.storageKey)
        mockDelay.interval = expectedDelay

        let exponent: Int16 = -2
        let startTime = Date()

        let voucher = try await allocator.allocate(exponent: exponent)
        let endTime = Date()

        #expect(voucher.derivationIndex == expectedIndex)
        #expect(voucher.exponent == exponent)
        #expect(voucher.recycler == nil)

        #expect(voucher.allocatedAt >= startTime)
        #expect(voucher.allocatedAt <= endTime)

        let expectedReadyAt = voucher.allocatedAt.addingTimeInterval(expectedDelay)
        #expect(voucher.readyAt == expectedReadyAt)
    }

    @Test("Propagates errors during voucher allocation")
    func allocationFailures() async throws {
        try keychain.saveKey(Data("".utf8), with: store.storageKey)

        await #expect(throws: Error.self) {
            try await allocator.allocate(exponent: 0)
        }
    }
}

// MARK: - Mocks

private extension VoucherAllocatorTests {
    final class MockDelayProvider: VoucherDelayProviderProtocol {
        var interval: TimeInterval = 0
        func timeInterval() -> TimeInterval {
            interval
        }
    }
}
