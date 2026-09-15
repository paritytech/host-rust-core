import Foundation
import Foundation_iOS
import SubstrateSdk
import SubstrateStorageSubscription
import Individuality

enum DetermineStateSync {}

extension DetermineStateSync {
    struct MainChange: BatchStorageSubscriptionResult {
        enum Key: String {
            case candidate
            case mobRuleAlias
            case scoreAlias
            case resourcesAlias
            case keys
            case identity
            case consumerInfo
        }

        let candidate: UncertainStorage<ProofOfInkPallet.Candidate?>
        let mobRuleAlias: UncertainStorage<PeoplePallet.RevisedContextualAlias?>
        let scoreAlias: UncertainStorage<PeoplePallet.RevisedContextualAlias?>
        let resourcesAlias: UncertainStorage<PeoplePallet.RevisedContextualAlias?>
        let personId: UncertainStorage<PeoplePallet.PersonalId?>
        let identity: UncertainStorage<IdentityPallet.Identity?>
        let consumerInfo: UncertainStorage<ResourcesPallet.ConsumerInfo?>

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

            personId = try UncertainStorage<StringScaleMapper<PeoplePallet.PersonalId>?>(
                values: values,
                mappingKey: Key.keys.rawValue,
                context: context
            )
            .map { $0?.value }

            consumerInfo = try UncertainStorage(
                values: values,
                mappingKey: Key.consumerInfo.rawValue,
                context: context
            )

            identity = try UncertainStorage<IdentityPallet.Identity?>(
                values: values,
                mappingKey: Key.identity.rawValue,
                context: context
            )
        }

        var shouldWaitForPersonChange: Bool {
            guard case let .defined(value) = personId else {
                return true
            }
            return value != nil
        }
    }
}

extension DetermineStateSync {
    struct PersonChange: BatchStorageSubscriptionResult {
        enum Key: String {
            case personRecord
            case memberRingPosition
            case proofOfInkPerson
        }

        let personRecord: UncertainStorage<PeoplePallet.PersonRecord?>
        let memberRingPosition: UncertainStorage<MembersPallet.RingPosition?>
        let proofOfInkPerson: UncertainStorage<ProofOfInkPallet.Person?>

        init(
            values: [BatchStorageSubscriptionResultValue],
            blockHashJson _: JSON,
            context: [CodingUserInfoKey: Any]?
        ) throws {
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

            proofOfInkPerson = try UncertainStorage(
                values: values,
                mappingKey: Key.proofOfInkPerson.rawValue,
                context: context
            )
        }
    }
}

struct DetermineStateSyncState: Equatable {
    let candidate: ProofOfInkPallet.Candidate?
    let mobRuleAlias: PeoplePallet.RevisedContextualAlias?
    let scoreAlias: PeoplePallet.RevisedContextualAlias?
    let resourcesAlias: PeoplePallet.RevisedContextualAlias?
    let personId: PeoplePallet.PersonalId?
    let identity: IdentityPallet.Identity?
    let gamePlayer: GamePallet.Player?
    let gameParticipant: ScorePallet.Participant?
    let personRecord: PeoplePallet.PersonRecord?
    let memberRingPosition: MembersPallet.RingPosition?
    let proofOfInkPerson: ProofOfInkPallet.Person?
    let consumerInfo: ResourcesPallet.ConsumerInfo?
    let requiredScore: Int

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

    func applying(change: DetermineStateSync.MainChange) -> DetermineStateSyncState {
        .init(
            candidate: change.candidate.valueWhenDefined(else: candidate),
            mobRuleAlias: change.mobRuleAlias.valueWhenDefined(else: mobRuleAlias),
            scoreAlias: change.scoreAlias.valueWhenDefined(else: scoreAlias),
            resourcesAlias: change.resourcesAlias.valueWhenDefined(else: resourcesAlias),
            personId: change.personId.valueWhenDefined(else: personId),
            identity: change.identity.valueWhenDefined(else: identity),
            gamePlayer: gamePlayer,
            gameParticipant: gameParticipant,
            personRecord: personRecord,
            memberRingPosition: memberRingPosition,
            proofOfInkPerson: proofOfInkPerson,
            consumerInfo: change.consumerInfo.valueWhenDefined(else: consumerInfo),
            requiredScore: requiredScore
        )
    }

    func applying(change: DetermineStateSync.PersonChange) -> DetermineStateSyncState {
        .init(
            candidate: candidate,
            mobRuleAlias: mobRuleAlias,
            scoreAlias: scoreAlias,
            resourcesAlias: resourcesAlias,
            personId: personId,
            identity: identity,
            gamePlayer: gamePlayer,
            gameParticipant: gameParticipant,
            personRecord: change.personRecord.valueWhenDefined(else: personRecord),
            memberRingPosition: change.memberRingPosition.valueWhenDefined(else: memberRingPosition),
            proofOfInkPerson: change.proofOfInkPerson.valueWhenDefined(else: proofOfInkPerson),
            consumerInfo: consumerInfo,
            requiredScore: requiredScore
        )
    }

    func applying(result: GameInfoSubscriptionResult) -> DetermineStateSyncState {
        .init(
            candidate: candidate,
            mobRuleAlias: mobRuleAlias,
            scoreAlias: scoreAlias,
            resourcesAlias: resourcesAlias,
            personId: personId,
            identity: identity,
            gamePlayer: result.player.valueWhenDefined(else: gamePlayer),
            gameParticipant: gameParticipant,
            personRecord: personRecord,
            memberRingPosition: memberRingPosition,
            proofOfInkPerson: proofOfInkPerson,
            consumerInfo: consumerInfo,
            requiredScore: requiredScore
        )
    }

    func applying(result: ScoreInfoSubscriptionResult) -> DetermineStateSyncState {
        .init(
            candidate: candidate,
            mobRuleAlias: mobRuleAlias,
            scoreAlias: scoreAlias,
            resourcesAlias: resourcesAlias,
            personId: personId,
            identity: identity,
            gamePlayer: gamePlayer,
            gameParticipant: result.participant.valueWhenDefined(else: gameParticipant),
            personRecord: personRecord,
            memberRingPosition: memberRingPosition,
            proofOfInkPerson: proofOfInkPerson,
            consumerInfo: consumerInfo,
            requiredScore: requiredScore
        )
    }
}
