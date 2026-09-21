import Foundation
import Testing
import TrUAPIHost
@testable import polkadot_app

/// Class suite: a fresh instance per test gives each test its own defaults
/// suite (safe under parallel execution); deinit removes the domain.
final class TrUAPIStorageTests {
    private let defaults: UserDefaults
    private let suiteName: String

    init() throws {
        suiteName = "io.polkadotapp.tests.truapi-storage.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func productStorageRoundTrip() throws {
        let storage = TrUAPILocalStorage.createProductLocalStorage(
            productId: "test.product",
            defaults: defaults
        )
        let value = Data([0x01, 0x02])

        try storage.write(key: "k", value: value)
        #expect(try storage.read(key: "k") == value)

        try storage.clear(key: "k")
        #expect(try storage.read(key: "k") == nil)
    }

    @Test func productStorageIsolatesProducts() throws {
        let first = TrUAPILocalStorage.createProductLocalStorage(productId: "a", defaults: defaults)
        let second = TrUAPILocalStorage.createProductLocalStorage(productId: "b", defaults: defaults)

        try first.write(key: "k", value: Data([0x01]))

        #expect(try second.read(key: "k") == nil)
    }

    @Test func coreStorageRoundTrip() throws {
        let storage = TrUAPILocalStorage.createCoreLocalStorage(defaults: defaults)
        let key = Data([0x00]).toHex() // CoreStorageKey.AuthSession
        let value = Data([0xAA])

        try storage.write(key: key, value: value)
        #expect(try storage.read(key: key) == value)

        try storage.clear(key: key)
        #expect(try storage.read(key: key) == nil)
    }

    @Test func coreStorageIsolatedFromProductStorage() throws {
        let core = TrUAPILocalStorage.createCoreLocalStorage(defaults: defaults)
        let product = TrUAPILocalStorage.createProductLocalStorage(
            productId: "test.product",
            defaults: defaults
        )

        try core.write(key: "k", value: Data([0x01]))

        #expect(try product.read(key: "k") == nil)
    }

    @Test func independentNativeWalletRefusesRustPurseCustody() throws {
        let storage = CoreStorageBackend(storage: TrUAPILocalStorage.createCoreLocalStorage(defaults: defaults))
        // MainPurseCoinage is wallet-root/network scoped. Refusing its read is
        // essential: nil would authorize Core to create a competing allocator.
        let key = Data([13]) + Data(repeating: 0x42, count: 64)
        #expect(throws: HostRejection.self) { try storage.read(key: key) }
        #expect(throws: HostRejection.self) { try storage.write(key: key, value: Data([1])) }
        #expect(throws: HostRejection.self) { try storage.clear(key: key) }
    }

    @Test func nativeChatSnapshotsSurviveReadThenRepeatedReplacement() throws {
        let nonce = withUnsafeBytes(of: UUID().uuid) { Data($0) }
        let key = Data([16]) + nonce + nonce + Data(repeating: 0, count: 32)
        let storage = CoreStorageBackend(storage: TrUAPILocalStorage.createCoreLocalStorage(defaults: defaults))
        defer { try? storage.clear(key: key) }

        #expect(try storage.read(key: key) == nil)
        try storage.write(key: key, value: Data([1, 2]))
        #expect(try storage.read(key: key) == Data([1, 2]))
        try storage.write(key: key, value: Data([3, 4]))
        #expect(try storage.read(key: key) == Data([3, 4]))
        try storage.clear(key: key)
        #expect(try storage.read(key: key) == nil)
    }
}
