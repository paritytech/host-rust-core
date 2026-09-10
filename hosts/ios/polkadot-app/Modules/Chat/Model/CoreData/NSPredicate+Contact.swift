import Foundation
import SubstrateSdk

extension NSPredicate {
    static func contact(for accountId: AccountId) -> NSPredicate {
        NSPredicate(format: "%K == %@", #keyPath(CDChatContact.identifier), accountId.toHex())
    }

    static func blockedContacts() -> NSPredicate {
        NSPredicate(format: "%K == YES", #keyPath(CDChatContact.isBlocked))
    }

    static func pendingDevicesFanOutContacts() -> NSPredicate {
        NSPredicate(format: "%K == YES", #keyPath(CDChatContact.pendingDevicesFanOut))
    }
}
