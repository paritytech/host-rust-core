import Foundation
import SubstrateSdk
import SubstrateStorageSubscription
import Individuality

struct MemberStatusResult: BatchStorageSubscriptionResult {
    struct MemberUpdate {
        let derivationIndex: DerivationIndex
        let ringPosition: MembersPallet.RingPosition?
    }

    struct RingStatusUpdate {
        let derivationIndex: DerivationIndex
        let ringKeysStatus: MembersPallet.RingKeysStatus?
    }

    let ringPositionUpdates: [MemberUpdate]
    let ringStatusUpdates: [RingStatusUpdate]
    let blockHash: BlockHashData?

    init(
        values: [BatchStorageSubscriptionResultValue],
        blockHashJson: JSON,
        context: [CodingUserInfoKey: Any]?
    ) throws {
        var updates: [MemberUpdate] = []
        var ringStatusUpdates: [RingStatusUpdate] = []

        for item in values {
            guard
                let mappingKey = item.mappingKey,
                let subKey = SubscriptionKey(mappingKey: mappingKey)
            else {
                continue
            }

            switch subKey {
            case let .member(derivationIndex):
                let ringPosition = try? item.value.map(
                    to: MembersPallet.RingPosition?.self,
                    with: context
                )

                updates.append(.init(
                    derivationIndex: derivationIndex,
                    ringPosition: ringPosition
                ))

            case let .ringStatus(derivationIndex):
                let ringKeysStatus = try? item.value.map(
                    to: MembersPallet.RingKeysStatus?.self,
                    with: context
                )

                ringStatusUpdates.append(.init(
                    derivationIndex: derivationIndex,
                    ringKeysStatus: ringKeysStatus
                ))
            }
        }

        ringPositionUpdates = updates
        self.ringStatusUpdates = ringStatusUpdates
        blockHash = try blockHashJson.map(to: BlockHashData?.self, with: context)
    }
}
