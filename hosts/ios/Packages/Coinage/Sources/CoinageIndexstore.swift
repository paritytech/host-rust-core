import Foundation
import Keystore_iOS
import SubstrateSdk

protocol CoinageIndexstoreProtocol {
    func getNextIndex() throws -> DerivationIndex
    func getCurrentIndex() throws -> DerivationIndex?
    func setCurrentIndex(_ index: DerivationIndex) throws

    var storageKey: String { get }
    var storage: KeystoreProtocol { get }
}

/// The index is persisted SCALE-encoded as `UInt64`.
extension CoinageIndexstoreProtocol {
    func getNextIndex() throws -> DerivationIndex {
        guard let current = try getCurrentIndex() else {
            try setCurrentIndex(0)
            return 0
        }

        let next = current + 1
        try setCurrentIndex(next)
        return next
    }

    func getCurrentIndex() throws -> DerivationIndex? {
        guard try storage.checkKey(for: storageKey) else { return nil }
        let data = try storage.fetchKey(for: storageKey)
        return try DerivationIndex(scaleDecoder: ScaleDecoder(data: data))
    }

    func setCurrentIndex(_ index: DerivationIndex) throws {
        try storage.saveKey(index.scaleEncoded(), with: storageKey)
    }
}

final class CoinIndexstore: CoinageIndexstoreProtocol {
    let storage: KeystoreProtocol
    let storageKey = "coin-index-store-v2"

    init(storage: KeystoreProtocol) {
        self.storage = storage
    }
}

final class VoucherIndexstore: CoinageIndexstoreProtocol {
    let storage: KeystoreProtocol
    let storageKey = "voucher-index-store-v2"

    init(storage: KeystoreProtocol) {
        self.storage = storage
    }
}
