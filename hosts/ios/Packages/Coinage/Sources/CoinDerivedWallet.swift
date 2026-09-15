import Foundation
import SubstrateSdk
import SubstrateSdkExt
import Keystore_iOS
import NovaCrypto
import KeyDerivation

enum CoinDerivedWalletError: Error {
    case unexpectedAccount
}

struct CoinDerivedWallet {
    private let keypair: SNKeypairProtocol

    init(privateKey: PrivateKey, publicKey: PublicKey) throws {
        try keypair = SNKeypair(
            privateKey: .init(rawData: privateKey),
            publicKey: .init(rawData: publicKey)
        )
    }
}

extension CoinDerivedWallet: WalletManaging {
    func getRawPublicKey() throws -> Data {
        keypair.publicKey().rawData()
    }

    func fetchAccount(for chain: ChainProtocol) throws -> AccountProtocol {
        CoinDerivedAccount(snPublicKey: keypair.publicKey(), chain: chain)
    }

    func hasAccount(in _: ChainProtocol) -> Bool {
        true
    }

    func fetchSignerSecret(for signer: SignerProviding) throws -> Data {
        guard signer.account?.accountId == keypair.publicKey().rawData() else {
            throw CoinDerivedWalletError.unexpectedAccount
        }

        return keypair.privateKey().rawData()
    }

    func fetchRawSecretKey() throws -> Data {
        keypair.privateKey().rawData()
    }

    func getMultiSigner() throws -> MultiSigner {
        let publicKey = try getRawPublicKey()
        return .sr25519(publicKey)
    }

    func sign(data: Data) throws -> MultiSignature {
        let rawSignature = try DefaultSigningWrapper(
            secretProvider: self
        )
        .sign(
            data,
            context: .rawBytes(keypair.publicKey())
        )
        .rawData()

        return .sr25519(data: rawSignature)
    }
}

struct CoinDerivedAccount {
    let snPublicKey: SNPublicKey
    let chain: ChainProtocol
}

extension CoinDerivedAccount: AccountProtocol {
    var accountId: AccountId { snPublicKey.accountId }
    var publicKey: Data { snPublicKey.rawData() }
    var signatureFormat: ExtrinsicSignatureFormat { snPublicKey.signatureFormat }
    var signaturePayloadFormat: ExtrinsicSignaturePayloadFormat { snPublicKey.signaturePayloadFormat }
    var signatureType: CryptoType { snPublicKey.signatureType }

    func toAddress() throws -> AccountAddress {
        try accountId.toAddress(using: .substrate(chain.base58Prefix))
    }
}

public extension SNPublicKey {
    var accountId: AccountId {
        rawData()
    }

    var publicKey: Data {
        rawData()
    }

    var signatureFormat: ExtrinsicSignatureFormat {
        .substrate
    }

    var signaturePayloadFormat: ExtrinsicSignaturePayloadFormat {
        .regular
    }

    var signatureType: CryptoType { .sr25519 }
}
