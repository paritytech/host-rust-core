import Testing
import Foundation
import SubstrateSdk
import Keystore_iOS
@testable import Coinage

struct CoinageIndexstoreTests {
    let keychain: InMemoryKeychain
    let coinIndexstore: CoinIndexstore
    let voucherIndexstore: VoucherIndexstore

    // Runs before each test case
    init() {
        keychain = InMemoryKeychain()
        coinIndexstore = CoinIndexstore(storage: keychain)
        voucherIndexstore = VoucherIndexstore(storage: keychain)
    }

    @Test("CoinKeystore increments index correctly")
    func coinIndexstoreIncrement() throws {
        let firstIndex = try coinIndexstore.getNextIndex()
        #expect(firstIndex == 0)

        let secondIndex = try coinIndexstore.getNextIndex()
        #expect(secondIndex == 1)

        // Verify persistence in keychain
        let storedData = try keychain.fetchKey(for: coinIndexstore.storageKey)
        let decoder = try ScaleDecoder(data: storedData)
        let storedIndex = try UInt64(scaleDecoder: decoder)
        #expect(storedIndex == 1)
    }

    @Test("VoucherKeystore increments index correctly")
    func voucherIndexstoreIncrement() throws {
        // Seed with index 10
        let initialIndex: UInt64 = 10
        try keychain.saveKey(initialIndex.scaleEncoded(), with: voucherIndexstore.storageKey)

        let nextIndex = try voucherIndexstore.getNextIndex()
        #expect(nextIndex == 11)
    }

    @Test("Keystores are isolated from each other")
    func indexstoreIsolation() throws {
        // Seed both with different values
        try keychain.saveKey(UInt64(100).scaleEncoded(), with: coinIndexstore.storageKey)
        try keychain.saveKey(UInt64(500).scaleEncoded(), with: voucherIndexstore.storageKey)

        let nextCoin = try coinIndexstore.getNextIndex()
        let nextVoucher = try voucherIndexstore.getNextIndex()

        #expect(nextCoin == 101)
        #expect(nextVoucher == 501)

        // Verify storage keys are distinct
        #expect(coinIndexstore.storageKey == "coin-index-store-v2")
        #expect(voucherIndexstore.storageKey == "voucher-index-store-v2")
    }
}
