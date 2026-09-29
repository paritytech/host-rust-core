import Foundation
import SubstrateSdk
import Individuality

enum PersonRegistration {
    enum IntendedType {
        case proofOfInk
        case game
    }

    enum CandidateType {
        case proofOfInk(ProofOfInkCandidateType)
        case game(isSuspended: Bool)

        init(candidate: ProofOfInkPallet.Candidate) {
            switch candidate {
            case let .applied(applied):
                self.init(cred: applied.cred)
            case let .selected(selected):
                self.init(cred: selected.cred)
            case let .proven(proven):
                self.init(proven: proven)
            }
        }

        private init(cred: ProofOfInkPallet.Candidate.Credibility) {
            switch cred {
            case .referred:
                self = .proofOfInk(.referred)
            case .deposit:
                self = .proofOfInk(.deposit)
            case .invited:
                self = .proofOfInk(.invited)
            }
        }

        private init(proven: ProofOfInkPallet.Candidate.Proven) {
            if proven.wasReferred {
                self = .proofOfInk(.referred)
            } else if proven.wasInvited {
                self = .proofOfInk(.invited)
            } else {
                self = .proofOfInk(.deposit)
            }
        }

        var isReferred: Bool {
            switch self {
            case let .proofOfInk(type):
                type.isReferred
            case .game:
                false
            }
        }
    }

    enum ProofOfInkCandidateType {
        case referred
        case deposit
        case invited

        var isReferred: Bool {
            switch self {
            case .referred:
                true
            case .deposit,
                 .invited:
                false
            }
        }
    }

    struct RemoteState: Equatable {
        let proofOfInkCandidate: ProofOfInkPallet.Candidate?
        let gameCandidate: ScorePallet.Participant?
        let personalId: PeoplePallet.PersonalId?
        let mobRuleAlias: PeoplePallet.RevisedContextualAlias?
        let scoreAlias: PeoplePallet.RevisedContextualAlias?
        let resourcesAlias: PeoplePallet.RevisedContextualAlias?
        let personRecord: PeoplePallet.PersonRecord?
        let memberRingPosition: MembersPallet.RingPosition?
        let keysStatus: MembersPallet.RingKeysStatus?
        let bestBlockTimestampMs: BlockTime?
        let collectionInfo: MembersPallet.CollectionInfo?
        let ringsState: MembersPallet.RingMembersState?
        let blockHash: Data?

        func applyingChange(_ change: PersonhoodRegistrationSyncChange) -> RemoteState {
            .init(
                proofOfInkCandidate: change.proofOfInkCandidate.valueWhenDefined(else: proofOfInkCandidate),
                gameCandidate: change.gameCandidate.valueWhenDefined(else: gameCandidate),
                personalId: change.personalId.valueWhenDefined(else: personalId),
                mobRuleAlias: change.mobRuleAlias.valueWhenDefined(else: mobRuleAlias),
                scoreAlias: change.scoreAlias.valueWhenDefined(else: scoreAlias),
                resourcesAlias: change.resourcesAlias.valueWhenDefined(else: resourcesAlias),
                personRecord: change.personRecord.valueWhenDefined(else: personRecord),
                memberRingPosition: change.memberRingPosition.valueWhenDefined(else: memberRingPosition),
                keysStatus: change.keysStatus.valueWhenDefined(else: keysStatus),
                bestBlockTimestampMs: change.bestBlockTimestampMs.valueWhenDefined(else: bestBlockTimestampMs),
                collectionInfo: change.collectionInfo.valueWhenDefined(else: collectionInfo),
                ringsState: change.ringsState.valueWhenDefined(else: ringsState),
                blockHash: change.blockHash
            )
        }

        func registrableCandidateType() -> CandidateType? {
            if let proofOfInkCandidate, hasProvenCandidate {
                return CandidateType(candidate: proofOfInkCandidate)
            }

            if let gameCandidate, gameCandidate.reachedPersonhood {
                return .game(isSuspended: gameCandidate.recognition.isSuspended)
            }

            return nil
        }

        private var hasProvenCandidate: Bool {
            if case .proven = proofOfInkCandidate {
                true
            } else {
                false
            }
        }

        var isNotSuspendedPerson: Bool {
            if memberRingPosition?.isSuspended == true {
                return false
            }
            if gameCandidate?.recognition.isSuspended == true {
                return false
            }
            return personalId != nil
        }

        var hasPersonalRecord: Bool {
            personRecord != nil
        }

        var hasPersonalIdAccount: Bool {
            personRecord?.account != nil
        }

        var hasRelevantAliases: Bool {
            [mobRuleAlias, scoreAlias, resourcesAlias].allSatisfy {
                hasRelevantAlias(alias: $0)
            }
        }

        func hasRelevantAlias(alias: PeoplePallet.RevisedContextualAlias?) -> Bool {
            guard let memberRingPosition else {
                return false
            }
            return alias.isRelevant(accordingTo: memberRingPosition)
        }

        var isRegistrationFinished: Bool {
            isNotSuspendedPerson && hasPersonalIdAccount && hasRelevantAliases
        }

        var selfIncludeEligibility: SelfIncludeEligibility {
            SelfIncludeEligibility.evaluate(
                position: memberRingPosition,
                collectionInfo: collectionInfo,
                ringsState: ringsState,
                bestBlockTimestampMs: bestBlockTimestampMs
            )
        }
    }

    enum SelfIncludeEligibility: Equatable {
        case unavailable
        case notOnboarding
        case waiting
        case eligible(callValidAt: UInt64) // timestamp in seconds

        static func evaluate(
            position: MembersPallet.RingPosition?,
            collectionInfo: MembersPallet.CollectionInfo?,
            ringsState: MembersPallet.RingMembersState?,
            bestBlockTimestampMs: BlockTime?
        ) -> Self {
            guard let position else {
                return .notOnboarding
            }
            guard let selfInclusionDelay = collectionInfo?.selfInclusionDelay else {
                return .unavailable
            }
            guard position.isOnboarding,
                  let queuedAt = position.onboardingQueuedAt else {
                return .notOnboarding
            }
            guard ringsState?.appendOnly == true else {
                // Chain rejects self_include unless RingsState == AppendOnly
                return .waiting
            }
            guard let bestBlockTimestampMs else {
                return .waiting
            }
            let nowSeconds = bestBlockTimestampMs / 1_000
            if nowSeconds >= queuedAt + selfInclusionDelay {
                return .eligible(callValidAt: nowSeconds)
            } else {
                return .waiting
            }
        }
    }

    struct LocalState: Codable {
        enum Error: Codable {
            case failedPersonRegistration
            case failedCreatingAlias
            case failedSettingPersonalIdAccount
            case failedSelfInclude
        }

        let progress: Progress
        let error: Error?

        func changing(error: Error?) -> LocalState {
            .init(progress: progress, error: error)
        }

        func changing(progress: Progress) -> LocalState {
            .init(progress: progress, error: error)
        }
    }

    enum Progress: Codable {
        case notTriggered
        case idle
        case submittingRegisterPerson
        case submittingSelfInclude
        case submittingPersonalIdAccount
        case submittingMobRuleAlias
        case submittingScoreAlias
        case submittingResourcesAlias

        var isNotTriggered: Bool {
            switch self {
            case .notTriggered:
                true
            default:
                false
            }
        }

        var isIdle: Bool {
            switch self {
            case .idle:
                true
            default:
                false
            }
        }

        var isRegisteringPerson: Bool {
            switch self {
            case .submittingRegisterPerson:
                true
            default:
                false
            }
        }

        var isSubmittingPersonalIdAccount: Bool {
            switch self {
            case .submittingPersonalIdAccount:
                true
            default:
                false
            }
        }

        var isSubmittingSelfInclude: Bool {
            switch self {
            case .submittingSelfInclude:
                true
            default:
                false
            }
        }
    }
}
