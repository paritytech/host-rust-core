import Foundation
import Keystore_iOS
import SubstrateSdk
import KeyDerivation

protocol PrivacyVoucherKeyFactoryProtocol {
    func deriveKey(for derivationPath: String) throws -> MemberKeyData
}

final class PrivacyVoucherKeyFactory {
    private let entropyManager: RootEntropyManaging
    private let memberKeyService: MemberKeyServicing

    init(
        memberKeyService: MemberKeyServicing = MemberKeyService(),
        entropyManager: RootEntropyManaging = RootEntropyManager.shared
    ) {
        self.memberKeyService = memberKeyService
        self.entropyManager = entropyManager
    }
}

extension PrivacyVoucherKeyFactory: PrivacyVoucherKeyFactoryProtocol {
    func deriveKey(for derivationPath: String) throws -> MemberKeyData {
        let keypair = try WalletMnemonicKeypairFactory(
            derivationPath: derivationPath,
            entropyManager: entropyManager
        ).deriveKeypair()

        let bandersnatchEntropy = keypair.privateKey().rawData().prefix(32)
        let keys = try memberKeyService.deriveNewMemberKey(from: bandersnatchEntropy).get()

        return MemberKeyData(entropy: keys.entropy, memberKey: keys.memberKey)
    }
}
