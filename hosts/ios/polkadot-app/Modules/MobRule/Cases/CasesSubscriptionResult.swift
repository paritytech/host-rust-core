import Foundation
import SubstrateSdk
import SubstrateStorageSubscription
import Individuality

struct CasesSubscriptionResult<Case: Decodable>: BatchStorageSubscriptionResult {
    let cases: [MobRulePallet.CaseIndex: Case]
    let blockHash: Data?

    init(
        values: [BatchStorageSubscriptionResultValue],
        blockHashJson: JSON,
        context: [CodingUserInfoKey: Any]?
    ) throws {
        cases = values.reduce(into: [:]) { dict, result in
            guard let mappingKey = result.mappingKey,
                  let caseIndex = MobRulePallet.CaseIndex(mappingKey),
                  let value = try? result.value.map(to: Case.self, with: context) else {
                return
            }
            dict[caseIndex] = value
        }

        blockHash = try blockHashJson.map(to: Data?.self, with: context)
    }
}

typealias DoneCasesSubscriptionResult = CasesSubscriptionResult<MobRulePallet.DoneCase>
