import Foundation
import Keystore_iOS
import KeyDerivation

extension RootEntropyManager {
    static let shared = RootEntropyManager(
        keychain: Keychain(),
        userDefaults: SharedContainerGroup.userDefaults
    )
}
