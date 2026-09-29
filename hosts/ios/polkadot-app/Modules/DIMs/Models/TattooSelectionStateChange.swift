import Foundation
import Foundation_iOS
import SubstrateSdk
import SubstrateStorageSubscription
import Individuality

struct TattooSelectionStateChange: BatchStorageSubscriptionResult {
    enum Key: String {
        case candidate
        case account
        case nextPersonalId
    }

    let candidate: UncertainStorage<ProofOfInkPallet.Candidate?>
    let account: UncertainStorage<SystemPallet.AccountInfo?>
    let personalId: UncertainStorage<ProofOfInkPallet.PersonalId>

    init(
        values: [BatchStorageSubscriptionResultValue],
        blockHashJson _: JSON,
        context: [CodingUserInfoKey: Any]?
    ) throws {
        candidate = try UncertainStorage(
            values: values,
            mappingKey: Key.candidate.rawValue,
            context: context
        )

        account = try UncertainStorage(
            values: values,
            mappingKey: Key.account.rawValue,
            context: context
        )

        personalId = try UncertainStorage<OptionStringCodable<ProofOfInkPallet.PersonalId>>(
            values: values,
            mappingKey: Key.nextPersonalId.rawValue,
            context: context
        )
        .map { $0.wrappedValue ?? 0 }
    }
}

struct TattooSelectionState: Equatable {
    let candidate: ProofOfInkPallet.Candidate?
    let account: SystemPallet.AccountInfo?
    let personalId: ProofOfInkPallet.PersonalId

    func applying(change: TattooSelectionStateChange) -> TattooSelectionState {
        .init(
            candidate: change.candidate.valueWhenDefined(else: candidate),
            account: change.account.valueWhenDefined(else: account),
            personalId: change.personalId.valueWhenDefined(else: personalId)
        )
    }
}
