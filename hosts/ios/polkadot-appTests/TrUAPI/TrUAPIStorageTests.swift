import Foundation
import Testing
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
}
