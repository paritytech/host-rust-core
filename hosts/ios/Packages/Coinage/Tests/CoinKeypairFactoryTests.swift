import Testing
import Foundation
import SubstrateSdk
import NovaCrypto
import KeyDerivation
@testable import Coinage

struct CoinKeypairFactoryTests {
    private let mockEntropyManager: MockEntropyManager
    private let factory: CoinKeypairFactory

    init() {
        mockEntropyManager = MockEntropyManager()
        factory = CoinKeypairFactory(entropyManager: mockEntropyManager)
    }

    @Test("Successfully creates public key when entropy is present")
    func derivePublicKeySuccess() throws {
        let validEntropy = Data(repeating: 0x01, count: 32)
        try mockEntropyManager.createRootEntropy(validEntropy)

        let publicKey = try factory.derivePublicKey(index: 1)

        #expect(publicKey.count == 32)
    }

    @Test("Throws error when entropy is missing")
    func derivePublicKeyMissingEntropy() throws {
        #expect(throws: RootEntropyManagerError.noEntropyFound) {
            _ = try factory.derivePublicKey(index: 1)
        }
    }

    @Test("Derives deterministic keys for same entropy and index")
    func deterministicDerivation() throws {
        let entropy = Data(repeating: 0xAB, count: 32)
        try mockEntropyManager.createRootEntropy(entropy)

        let manager2 = MockEntropyManager(entropy: entropy)
        let factory2 = CoinKeypairFactory(entropyManager: manager2)

        let key1 = try factory.derivePublicKey(index: 5)
        let key2 = try factory2.derivePublicKey(index: 5)

        #expect(key1 == key2)
    }

    @Test("Derives different keys for different indices")
    func differentIndicesProduceDifferentKeys() throws {
        let entropy = Data(repeating: 0xAB, count: 32)
        try mockEntropyManager.createRootEntropy(entropy)

        let key1 = try factory.derivePublicKey(index: 1)
        let key2 = try factory.derivePublicKey(index: 2)

        #expect(key1 != key2)
    }

    @Test("Base derivation path is correct")
    func derivationPathCorrectness() {
        #expect(factory.coinPath(for: 123) == "//coinage//4294967295//0/123")
    }
}
