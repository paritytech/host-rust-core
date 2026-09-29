import Foundation
import Products
import SubstrateSdk
import SubstrateSdkExt

struct CreateTransactionPayloadExtensions {
    struct ExistingParameters: OptionSet {
        let rawValue: UInt8

        static let nonce = ExistingParameters(rawValue: 1 << 0)
        static let mortality = ExistingParameters(rawValue: 1 << 1)
        static let disabledVerifySignature = ExistingParameters(rawValue: 1 << 2)
    }

    let existingParameters: ExistingParameters
    let customExtensions: [TransactionExtending]
}

final class CreateTransactionExtensionResolver {
    func resolve(
        extensions: [EncodedTransactionExtensionValue],
        codingFactory: RuntimeCoderFactoryProtocol
    ) throws -> CreateTransactionPayloadExtensions {
        var existingParameters: CreateTransactionPayloadExtensions.ExistingParameters = []
        var customExtensions: [TransactionExtending] = []

        for ext in extensions {
            switch ext.id {
            case Extrinsic.TransactionExtensionId.nonce:
                existingParameters.insert(.nonce)
            case Extrinsic.TransactionExtensionId.mortality:
                existingParameters.insert(.mortality)
            case Extrinsic.TransactionExtensionId.verifySignature:
                if isDisabledVerifySignature(ext: ext, codingFactory: codingFactory) {
                    existingParameters.insert(.disabledVerifySignature)
                }
            default:
                break
            }

            guard let coder = resolveExtensionCoder(
                for: ext.id,
                metadata: codingFactory.metadata
            ) else {
                continue
            }

            let decodedExplicit = try decodeExplicitJSON(
                ext: ext,
                coder: coder,
                codingFactory: codingFactory
            )

            customExtensions.append(
                RawTransactionExtension(
                    txExtensionId: ext.id,
                    rawImplicit: ext.implicit,
                    decodedExplicit: decodedExplicit,
                    coder: coder
                )
            )
        }

        return CreateTransactionPayloadExtensions(
            existingParameters: existingParameters,
            customExtensions: customExtensions
        )
    }
}

private extension CreateTransactionExtensionResolver {
    func isDisabledVerifySignature(
        ext: EncodedTransactionExtensionValue,
        codingFactory: RuntimeCoderFactoryProtocol
    ) -> Bool {
        guard let coder = resolveExtensionCoder(
            for: ext.id,
            metadata: codingFactory.metadata
        ) else {
            return false
        }

        guard let json = try? decodeExplicitJSON(
            ext: ext,
            coder: coder,
            codingFactory: codingFactory
        ) else {
            return false
        }

        guard let mode = try? json.map(
            to: TransactionExtension.VerifySignature.Mode.self
        ) else {
            return false
        }

        if case .disabled = mode {
            return true
        }

        return false
    }

    func decodeExplicitJSON(
        ext: EncodedTransactionExtensionValue,
        coder: TransactionExtensionCoding,
        codingFactory: RuntimeCoderFactoryProtocol
    ) throws -> JSON? {
        guard !ext.explicit.isEmpty else { return nil }

        let decoder = try codingFactory.createDecoder(from: ext.explicit)
        var extraStore: ExtrinsicExtra = [:]
        try coder.decodeIncludedInExtrinsic(to: &extraStore, decoder: decoder)

        return extraStore[ext.id]
    }

    func resolveExtensionCoder(
        for extensionId: String,
        metadata: RuntimeMetadataProtocol
    ) -> TransactionExtensionCoding? {
        switch extensionId {
        case Extrinsic.TransactionExtensionId.mortality:
            return TransactionExtension.CheckMortality.getTransactionExtensionCoder()
        case Extrinsic.TransactionExtensionId.nonce:
            return TransactionExtension.CheckNonce.getTransactionExtensionCoder()
        case Extrinsic.TransactionExtensionId.txPayment:
            return TransactionExtension.ChargeTransactionPayment.getTransactionExtensionCoder()
        case Extrinsic.TransactionExtensionId.checkMetadataHash:
            return CheckMetadataHashCoder()
        default:
            guard let typeName = metadata.getSignedExtensionType(for: extensionId) else {
                return nil
            }

            return DefaultTransactionExtensionCoder(
                txExtensionId: extensionId,
                extensionExplicitType: typeName
            )
        }
    }
}
