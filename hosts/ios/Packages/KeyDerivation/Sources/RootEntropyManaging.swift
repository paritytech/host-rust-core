import Foundation
import Keystore_iOS

public protocol RootEntropyManaging {
    func fetchRootEntropy() throws -> Data
    func createRootEntropy(_ entropy: Data) throws
    func hasRootEntropy() throws -> Bool
}

public protocol RootEntropyIdStoring {
    func saveEntropyId(_ entropyId: String)
    func getEntropyId() -> String?
}

public class RootEntropyIdStore: RootEntropyIdStoring {
    static let entropyIdKey: String = "io.polkadot.app.entropy.id.v2"

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    public func saveEntropyId(_ entropyId: String) {
        userDefaults.set(entropyId, forKey: Self.entropyIdKey)
        userDefaults.synchronize()
    }

    public func getEntropyId() -> String? {
        userDefaults.string(forKey: Self.entropyIdKey)
    }
}

public enum RootEntropyManagerError: Error {
    case noEntropyFound
}

public final class RootEntropyManager {
    let keychain: KeystoreProtocol
    let entropyIdStore: RootEntropyIdStoring

    public convenience init(
        keychain: KeystoreProtocol,
        userDefaults: UserDefaults
    ) {
        self.init(
            keychain: keychain,
            entropyIdStore: RootEntropyIdStore(userDefaults: userDefaults)
        )
    }

    public init(
        keychain: KeystoreProtocol,
        entropyIdStore: RootEntropyIdStoring
    ) {
        self.keychain = keychain
        self.entropyIdStore = entropyIdStore
    }
}

extension RootEntropyManager: RootEntropyManaging {
    public func hasRootEntropy() throws -> Bool {
        guard let entropyId = entropyIdStore.getEntropyId() else {
            return false
        }

        return try keychain.checkKey(for: KeystoreTag.rootEntropyTag(for: entropyId))
    }

    public func fetchRootEntropy() throws -> Data {
        guard let entropyId = entropyIdStore.getEntropyId() else {
            throw RootEntropyManagerError.noEntropyFound
        }

        return try keychain.fetchKey(for: KeystoreTag.rootEntropyTag(for: entropyId))
    }

    public func createRootEntropy(_ entropy: Data) throws {
        let newEntropyId = UUID().uuidString
        entropyIdStore.saveEntropyId(newEntropyId)
        try keychain.saveKey(entropy, with: KeystoreTag.rootEntropyTag(for: newEntropyId))
    }
}
