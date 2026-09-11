import Foundation
import SubstrateSdk
import SubstrateStorageSubscription

struct WithdrawalAddressBalanceResult: BatchStorageSubscriptionResult {
    let infoByIdentifier: [String: SystemPallet.AccountInfo]

    init(
        values: [BatchStorageSubscriptionResultValue],
        blockHashJson _: JSON,
        context: [CodingUserInfoKey: Any]?
    ) throws {
        infoByIdentifier = values.reduce(into: [:]) { dict, result in
            guard
                let identifier = result.mappingKey,
                let value = try? result.value.map(to: SystemPallet.AccountInfo.self, with: context)
            else {
                return
            }
            dict[identifier] = value
        }
    }
}
