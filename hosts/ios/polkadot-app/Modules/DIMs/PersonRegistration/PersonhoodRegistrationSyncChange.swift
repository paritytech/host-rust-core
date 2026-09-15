import Foundation
import Foundation_iOS
import SubstrateSdk
import SubstrateStorageSubscription
import Individuality

struct PersonhoodRegistrationSyncChange: BatchStorageSubscriptionResult {
    enum Key: String {
        case keys
        case mobRuleAlias
        case scoreAlias
        case resourcesAlias
        case proofOfInkCandidate
        case gameCandidate
        case personRecord
        case memberRingPosition
        case keysStatus
        case bestBlockTimestamp
        case collectionInfo
        case ringsState
    }

    let personalId: UncertainStorage<PeoplePallet.PersonalId?>
    let mobRuleAlias: UncertainStorage<PeoplePallet.RevisedContextualAlias?>
    let scoreAlias: UncertainStorage<PeoplePallet.RevisedContextualAlias?>
    let resourcesAlias: UncertainStorage<PeoplePallet.RevisedContextualAlias?>
    let proofOfInkCandidate: UncertainStorage<ProofOfInkPallet.Candidate?>
    let gameCandidate: UncertainStorage<ScorePallet.Participant?>
    let personRecord: UncertainStorage<PeoplePallet.PersonRecord?>
    let memberRingPosition: UncertainStorage<MembersPallet.RingPosition?>
    let keysStatus: UncertainStorage<MembersPallet.RingKeysStatus?>
    let bestBlockTimestampMs: UncertainStorage<BlockTime?>
    let collectionInfo: UncertainStorage<MembersPallet.CollectionInfo?>
    let ringsState: UncertainStorage<MembersPallet.RingMembersState?>
    let blockHash: Data?

    init(
        values: [BatchStorageSubscriptionResultValue],
        blockHashJson: JSON,
        context: [CodingUserInfoKey: Any]?
    ) throws {
        personalId = try UncertainStorage<StringScaleMapper<PeoplePallet.PersonalId>?>(
            values: values,
            mappingKey: Key.keys.rawValue,
            context: context
        )
        .map { $0?.value }

        mobRuleAlias = try UncertainStorage(
            values: values,
            mappingKey: Key.mobRuleAlias.rawValue,
            context: context
        )

        scoreAlias = try UncertainStorage(
            values: values,
            mappingKey: Key.scoreAlias.rawValue,
            context: context
        )

        resourcesAlias = try UncertainStorage(
            values: values,
            mappingKey: Key.resourcesAlias.rawValue,
            context: context
        )

        proofOfInkCandidate = try UncertainStorage(
            values: values,
            mappingKey: Key.proofOfInkCandidate.rawValue,
            context: context
        )

        gameCandidate = try UncertainStorage(
            values: values,
            mappingKey: Key.gameCandidate.rawValue,
            context: context
        )

        personRecord = try UncertainStorage(
            values: values,
            mappingKey: Key.personRecord.rawValue,
            context: context
        )

        memberRingPosition = try UncertainStorage(
            values: values,
            mappingKey: Key.memberRingPosition.rawValue,
            context: context
        )

        keysStatus = try UncertainStorage(
            values: values,
            mappingKey: Key.keysStatus.rawValue,
            context: context
        )

        bestBlockTimestampMs = try UncertainStorage<StringScaleMapper<BlockTime>?>(
            values: values,
            mappingKey: Key.bestBlockTimestamp.rawValue,
            context: context
        )
        .map { $0?.value }

        collectionInfo = try UncertainStorage(
            values: values,
            mappingKey: Key.collectionInfo.rawValue,
            context: context
        )

        ringsState = try UncertainStorage(
            values: values,
            mappingKey: Key.ringsState.rawValue,
            context: context
        )

        blockHash = try blockHashJson.map(to: Data?.self, with: context)
    }
}

struct PersonhoodRegistrationSyncState: Equatable {
    let personalId: PeoplePallet.PersonalId?
    let mobRuleAlias: PeoplePallet.RevisedContextualAlias?
    let scoreAlias: PeoplePallet.RevisedContextualAlias?
    let resourcesAlias: PeoplePallet.RevisedContextualAlias?
    let memberRingPosition: MembersPallet.RingPosition?

    var hasRelevantAliases: Bool {
        guard
            let memberRingPosition,
            mobRuleAlias.isRelevant(accordingTo: memberRingPosition),
            scoreAlias.isRelevant(accordingTo: memberRingPosition),
            resourcesAlias.isRelevant(accordingTo: memberRingPosition)
        else {
            return false
        }
        return true
    }

    func applying(change: PersonhoodRegistrationSyncChange) -> PersonhoodRegistrationSyncState {
        .init(
            personalId: change.personalId.valueWhenDefined(else: personalId),
            mobRuleAlias: change.mobRuleAlias.valueWhenDefined(else: mobRuleAlias),
            scoreAlias: change.scoreAlias.valueWhenDefined(else: scoreAlias),
            resourcesAlias: change.resourcesAlias.valueWhenDefined(else: resourcesAlias),
            memberRingPosition: change.memberRingPosition.valueWhenDefined(else: memberRingPosition)
        )
    }
}
