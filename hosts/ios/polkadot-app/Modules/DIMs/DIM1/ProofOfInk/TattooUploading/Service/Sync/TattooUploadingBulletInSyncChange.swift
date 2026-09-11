import BulletinChain
import Foundation
import SubstrateSdk
import SubstrateStorageSubscription
import Foundation_iOS

struct TattooUploadingBulletInSyncChange: BatchStorageSubscriptionResult {
    enum Key: String {
        case authorizations
        case blockNumber
    }

    let authorizations: UncertainStorage<TransactionStoragePallet.Authorization?>
    let blockNumber: UncertainStorage<BlockNumber>

    init(
        values: [BatchStorageSubscriptionResultValue],
        blockHashJson _: JSON,
        context: [CodingUserInfoKey: Any]?
    ) throws {
        authorizations = try UncertainStorage(
            values: values,
            mappingKey: Key.authorizations.rawValue,
            context: context
        )

        blockNumber = try UncertainStorage<StringScaleMapper<BlockNumber>>(
            values: values,
            mappingKey: Key.blockNumber.rawValue,
            context: context
        ).map(\.value)
    }
}
