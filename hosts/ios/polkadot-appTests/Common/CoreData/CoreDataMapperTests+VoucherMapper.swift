import BigInt
import Coinage
import Foundation
import Operation_iOS
import Testing

@testable import polkadot_app

extension CoreDataMapperTests {
    @Suite("VoucherMapper")
    struct VoucherMapperTests {
        private let facade = UserDataStorageTestFacade()
        private var repo: AnyDataProviderRepository<Voucher> { facade.makeRepo(mapper: VoucherMapper()) }

        private func makeVoucher(
            derivationIndex: UInt64 = 50,
            remoteState: Voucher.OnChainState = .unlocated
        ) -> Voucher {
            let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
            return Voucher(
                exponent: 10,
                derivationIndex: derivationIndex,
                allocatedAt: now,
                readyAt: now.addingTimeInterval(3_600),
                remoteState: remoteState,
                publicKey: Data(repeating: UInt8(truncatingIfNeeded: derivationIndex), count: 32)
            )
        }

        @Test("remoteState .unlocated round-trips")
        func roundTripUnlocated() async throws {
            let original = makeVoucher(remoteState: .unlocated)
            try await repo.saveOperation({ [original] }, { [] }).asyncExecute()

            let result = try #require(
                try await repo.fetchOperation(by: { original.identifier }, options: .init()).asyncExecute()
            )
            #expect(result.exponent == original.exponent)
            #expect(result.derivationIndex == original.derivationIndex)
            #expect(result.allocatedAt == original.allocatedAt)
            #expect(result.readyAt == original.readyAt)
            #expect(result.remoteState == .unlocated)
        }

        @Test("remoteState .onboarding round-trips")
        func roundTripOnboarding() async throws {
            let original = makeVoucher(derivationIndex: 51, remoteState: .onboarding)
            try await repo.saveOperation({ [original] }, { [] }).asyncExecute()

            let result = try #require(
                try await repo.fetchOperation(by: { original.identifier }, options: .init()).asyncExecute()
            )
            #expect(result.remoteState == .onboarding)
        }

        @Test("remoteState .inRecycler preserves recycler index")
        func roundTripInRecycler() async throws {
            let original = makeVoucher(derivationIndex: 52, remoteState: .inRecycler(.init(index: 7, membersCount: 0)))
            try await repo.saveOperation({ [original] }, { [] }).asyncExecute()

            let result = try #require(
                try await repo.fetchOperation(by: { original.identifier }, options: .init()).asyncExecute()
            )
            guard case let .inRecycler(recycler) = result.remoteState else {
                Issue.record("Expected .inRecycler, got \(result.remoteState)")
                return
            }
            #expect(recycler.index == 7)
        }
    }
}
