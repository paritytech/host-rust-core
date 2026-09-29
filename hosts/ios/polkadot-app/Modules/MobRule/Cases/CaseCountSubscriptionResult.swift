import Foundation
import Foundation_iOS
import SubstrateSdk
import SubstrateStorageSubscription
import Individuality

struct CaseCountSubscriptionResult: BatchStorageSubscriptionResult {
    enum Key: String {
        case count
    }

    let count: MobRulePallet.CaseIndex?

    init(
        values: [BatchStorageSubscriptionResultValue],
        blockHashJson _: JSON,
        context: [CodingUserInfoKey: Any]?
    ) throws {
        count = try UncertainStorage<StringScaleMapper<MobRulePallet.CaseIndex>?>(
            values: values,
            mappingKey: Key.count.rawValue,
            context: context
        ).value??.value
    }
}
