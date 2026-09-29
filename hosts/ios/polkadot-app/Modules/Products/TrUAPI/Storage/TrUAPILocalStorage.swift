import Foundation

protocol TrUAPILocalStoring: AnyObject, Sendable {
    func read(key: String) throws -> Data?
    func write(key: String, value: Data) throws
    func clear(key: String) throws
}

/// UserDefaults-backed KV store for the TrUAPI core; values are stored as
/// raw `Data`. Product storage is product-scoped; core storage is
/// host-GLOBAL — its prefix must NOT include a product id, the auth-session
/// slot is shared across product cores.
final class TrUAPILocalStorage: TrUAPILocalStoring, @unchecked Sendable {
    private static let productKeyPrefix = "io.polkadotapp.truapi.product.store"
    private static let coreKeyPrefix = "io.polkadotapp.truapi.core"

    let keyPrefix: String
    private let defaults: UserDefaults

    init(keyPrefix: String, defaults: UserDefaults) {
        self.keyPrefix = keyPrefix
        self.defaults = defaults
    }

    static func createProductLocalStorage(
        productId: String,
        defaults: UserDefaults = .standard
    ) -> TrUAPILocalStorage {
        TrUAPILocalStorage(keyPrefix: "\(productKeyPrefix).\(productId)", defaults: defaults)
    }

    static func createCoreLocalStorage(
        defaults: UserDefaults = .standard
    ) -> TrUAPILocalStorage {
        TrUAPILocalStorage(keyPrefix: coreKeyPrefix, defaults: defaults)
    }

    func read(key: String) throws -> Data? {
        defaults.data(forKey: storageKey(key))
    }

    func write(key: String, value: Data) throws {
        defaults.set(value, forKey: storageKey(key))
    }

    func clear(key: String) throws {
        defaults.removeObject(forKey: storageKey(key))
    }
}

private extension TrUAPILocalStorage {
    func storageKey(_ key: String) -> String {
        "\(keyPrefix).\(key)"
    }
}
