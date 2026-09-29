import Foundation
import Foundation_iOS
import SubstrateSdk
import SubstrateStorageSubscription
import Individuality

struct AirdropEventStatusSubscriptionResult: BatchStorageSubscriptionResult {
    enum Key: String {
        case event
    }

    private struct EventStatusProbe: Decodable {
        let status: NewAirdropPallet.Status
    }

    let status: NewAirdropPallet.Status?
    let blockHash: Data?

    init(
        values: [BatchStorageSubscriptionResultValue],
        blockHashJson: JSON,
        context: [CodingUserInfoKey: Any]?
    ) throws {
        let event = try UncertainStorage<EventStatusProbe?>(
            values: values,
            mappingKey: Key.event.rawValue,
            context: context
        )
        status = event.valueWhenDefined(else: nil)?.status
        blockHash = try blockHashJson.map(to: Data?.self, with: context)
    }
}
