import KeyDerivation
import SubstrateSdk
import NovaCrypto

public protocol CoinKeyDeriving: CoinKeypairFactoryProtocol {}

public final class CoinKeypairFactory {
    let entropyManager: RootEntropyManaging

    public init(entropyManager: RootEntropyManaging) {
        self.entropyManager = entropyManager
    }
}

extension CoinKeypairFactory: CoinKeyDeriving {
    public func derivePublicKey(index: DerivationIndex) throws -> PublicKey {
        try WalletMnemonicKeypairFactory(
            derivationPath: coinPath(for: index),
            entropyManager: entropyManager
        )
        .derivePublicKey()
        .rawData()
    }

    public func derivePrivateKey(index: DerivationIndex) throws -> PrivateKey {
        try WalletMnemonicKeypairFactory(
            derivationPath: coinPath(for: index),
            entropyManager: entropyManager
        )
        .deriveKeypair()
        .privateKey()
        .rawData()
    }
}

public extension CoinKeypairFactory {
    func coinPath(for derivationIndex: DerivationIndex) -> String {
        let purse = CoinageConstants.Derivation.mainPurse
        let page = CoinageConstants.Derivation.page

        return "//coinage//\(purse)//\(page)/\(derivationIndex)"
    }
}
