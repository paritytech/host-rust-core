import BigInt
import Coinage
import Foundation
import Operation_iOS
import Testing

@testable import polkadot_app

extension CoreDataMapperTests {
    @Suite("VoucherLocationMapper")
    struct VoucherLocationMapperTests {
        private let facade = UserDataStorageTestFacade()
        private var fullRepo: AnyDataProviderRepository<Voucher> { facade.makeRepo(mapper: VoucherMapper()) }
        private var locationRepo: AnyDataProviderRepository<VoucherLocationUpdate> {
            facade.makeRepo(mapper: VoucherLocationMapper())
        }

        @Test("updates remoteState only, preserves other fields")
        func updatesLocationOnly() async throws {
            let now = Date(timeIntervalSinceReferenceDate: 2_000_000)
            let original = Voucher(
                exponent: 11,
                derivationIndex: 100,
                allocatedAt: now,
                readyAt: now.addingTimeInterval(2_400),
                remoteState: .unlocated,
                publicKey: Data(repeating: 0x64, count: 32)
            )
            try await fullRepo.saveOperation({ [original] }, { [] }).asyncExecute()

            let updated = VoucherLocationUpdate(
                derivationIndex: 100,
                remoteState: .inRecycler(.init(index: 3, membersCount: 0))
            )

            try await locationRepo.saveOperation({ [updated] }, { [] }).asyncExecute()

            let result = try #require(
                try await fullRepo.fetchOperation(by: { original.identifier }, options: .init()).asyncExecute()
            )
            guard case let .inRecycler(recycler) = result.remoteState else {
                Issue.record("Expected .inRecycler, got \(result.remoteState)")
                return
            }
            #expect(recycler.index == 3)
            #expect(result.exponent == 11)
            #expect(result.derivationIndex == 100)
            #expect(result.allocatedAt == now)
            #expect(result.readyAt == now.addingTimeInterval(2_400))
        }

        @Test("throws missingVoucher when entity does not exist")
        func throwsForNewEntity() async throws {
            let update = VoucherLocationUpdate(
                derivationIndex: 999,
                remoteState: .onboarding
            )

            await #expect(throws: VoucherLocationMapper.MappingError.missingVoucher) {
                try await locationRepo.saveOperation({ [update] }, { [] }).asyncExecute()
            }
        }
    }
}
