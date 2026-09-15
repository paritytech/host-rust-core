import Foundation
import SubstrateSdk

@testable import polkadot_app

enum MockChatPeer {
    static func person(
        accountId: AccountId = Data(repeating: 0x01, count: 32)
    ) -> Chat.Peer {
        let contact = Chat.Contact(
            accountId: accountId,
            username: "test-user",
            publicKey: Data(repeating: 0x03, count: 32),
            ownKeyId: .init(signKeyId: "sign-key", encryptionKeyId: "enc-key"),
            source: .chat,
            isBlocked: false,
            devices: [],
            pendingDevicesFanOut: false
        )

        return .person(contact)
    }
}
