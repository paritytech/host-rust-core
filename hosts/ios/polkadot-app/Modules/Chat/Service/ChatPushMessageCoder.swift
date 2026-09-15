import Foundation
import MessageExchangeKit
import SubstrateSdk
import SubstrateSdkExt

protocol ChatPushMessageDecoding {
    func decodeMessage(
        _ message: String,
        for contact: Chat.Contact
    ) throws -> Chat.RemoteMessage
}

protocol ChatPushMessageEncoding {
    func encodeMessage(
        _ message: Chat.RemoteMessage,
        for contact: Chat.Contact
    ) throws -> String
}

typealias ChatPushMessageCoding = ChatPushMessageDecoding & ChatPushMessageEncoding

final class ChatPushMessageCoder {
    private let encryptionManager: MessageExchangeEncryptionManaging

    init(encryptionManager: MessageExchangeEncryptionManaging) {
        self.encryptionManager = encryptionManager
    }
}

extension ChatPushMessageCoder: ChatPushMessageCoding {
    func decodeMessage(
        _ message: String,
        for contact: Chat.Contact
    ) throws -> Chat.RemoteMessage {
        let encryptedData = try message.fromHex()
        let encryptor = try encryptionManager
            .makeEncryptorFactory(ownEncryptionKeyId: contact.ownKeyId.encryptionKeyId)
            .makeEncryptor(remotePublicKey: contact.publicKey)

        let decryptedData = try encryptor.decrypt(encryptedData)
        let decoder = try ScaleDecoder(data: decryptedData)

        return try Chat.RemoteMessage(scaleDecoder: decoder)
    }

    func encodeMessage(
        _ message: Chat.RemoteMessage,
        for contact: Chat.Contact
    ) throws -> String {
        let scaleData = try message.scaleEncoded()
        let encryptor = try encryptionManager
            .makeEncryptorFactory(ownEncryptionKeyId: contact.ownKeyId.encryptionKeyId)
            .makeEncryptor(remotePublicKey: contact.publicKey)

        let encryptedData = try encryptor.encrypt(scaleData)
        return encryptedData.toHex()
    }
}
