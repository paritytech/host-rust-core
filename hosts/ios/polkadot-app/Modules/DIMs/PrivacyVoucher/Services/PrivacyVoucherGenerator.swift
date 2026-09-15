import Foundation
import BandersnatchApi
import KeyDerivation

protocol PrivacyVoucherGenerating {
    func deriveKey(for type: PrivacyVoucherType, index: Int) throws -> MemberKeyData
    func generateLocalVoucher(with type: PrivacyVoucherType, index: Int) throws -> LocalPrivacyVoucher
}

final class PrivacyVoucherGenerator: PrivacyVoucherGenerating {
    private let keyFactory: PrivacyVoucherKeyFactoryProtocol

    init(
        keyFactory: PrivacyVoucherKeyFactoryProtocol = PrivacyVoucherKeyFactory()
    ) {
        self.keyFactory = keyFactory
    }

    func deriveKey(for type: PrivacyVoucherType, index: Int) throws -> MemberKeyData {
        try keyFactory.deriveKey(
            for: "//\(PrivacyVoucherPallet.context)//\(type.rawValue)//\(index)"
        )
    }

    func generateLocalVoucher(with type: PrivacyVoucherType, index: Int) throws -> LocalPrivacyVoucher {
        let key = try deriveKey(
            for: type,
            index: index
        )
        let alias = try BandersnatchApi.deriveAlias(
            fromEntropy: key.entropy,
            context: Data(PrivacyVoucherPallet.context.utf8)
        )
        return LocalPrivacyVoucher(
            key: key,
            alias: alias,
            type: type,
            index: index,
            isClaimed: false
        )
    }
}
