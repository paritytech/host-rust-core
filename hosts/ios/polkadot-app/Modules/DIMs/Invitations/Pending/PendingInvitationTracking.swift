import Foundation
import SubstrateSdk
import SubstrateStorageSubscription

enum PendingInvitationTracking {
    struct InvitationChange: BatchStorageSubscriptionResult {
        let inviteIssued: Bool

        init(
            values: [BatchStorageSubscriptionResultValue],
            blockHashJson _: JSON,
            context _: [CodingUserInfoKey: Any]?
        ) throws {
            guard let value = values.first?.value else {
                inviteIssued = false
                return
            }

            if case .null = value {
                inviteIssued = false
                return
            }

            // any value presented
            inviteIssued = true
        }
    }
}
