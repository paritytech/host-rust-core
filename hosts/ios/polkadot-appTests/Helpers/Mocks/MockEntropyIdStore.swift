import Foundation
import Keystore_iOS
import KeyDerivation

final class MockEntropyIdStore: RootEntropyIdStoring {
    private var entropyId: String?
    private let mutex = NSLock()

    func saveEntropyId(_ entropyId: String) {
        mutex.lock()

        defer {
            mutex.unlock()
        }

        self.entropyId = entropyId
    }

    func getEntropyId() -> String? {
        mutex.lock()

        defer {
            mutex.unlock()
        }

        return entropyId
    }
}
