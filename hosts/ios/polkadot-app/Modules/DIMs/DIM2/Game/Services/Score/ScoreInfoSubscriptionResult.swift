import Foundation
import Foundation_iOS
import SubstrateSdk
import SubstrateStorageSubscription
import Individuality

struct ScoreInfoSubscriptionResult: BatchStorageSubscriptionResult {
    enum Key: String {
        case participant
        case personhoodThreshold
    }

    let participant: UncertainStorage<ScorePallet.Participant?>
    let personhoodThreshold: UncertainStorage<UInt32?>
    let blockHash: Data?

    init(
        values: [BatchStorageSubscriptionResultValue],
        blockHashJson: JSON,
        context: [CodingUserInfoKey: Any]?
    ) throws {
        participant = try UncertainStorage(
            values: values,
            mappingKey: Key.participant.rawValue,
            context: context
        )

        personhoodThreshold = try UncertainStorage<StringCodable<UInt8>?>(
            values: values,
            mappingKey: Key.personhoodThreshold.rawValue,
            context: context
        )
        .map { $0.map { UInt32($0.wrappedValue) } }

        blockHash = try blockHashJson.map(to: Data?.self, with: context)
    }
}

struct ScoreInfoSyncData {
    let participant: ScorePallet.Participant?
    let requiredScore: UInt32?

    init(participant: ScorePallet.Participant? = nil, requiredScore: UInt32? = nil) {
        self.participant = participant
        self.requiredScore = requiredScore
    }
}

extension ScoreInfoSyncData {
    func applying(_ result: ScoreInfoSubscriptionResult) -> ScoreInfoSyncData {
        ScoreInfoSyncData(
            participant: result.participant.valueWhenDefined(else: participant),
            requiredScore: result.personhoodThreshold.valueWhenDefined(else: requiredScore)
        )
    }
}
