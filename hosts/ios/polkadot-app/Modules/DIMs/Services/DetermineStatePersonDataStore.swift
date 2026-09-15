import Foundation
import SubstrateSdk
import Individuality
import CommonService

final class DetermineStatePersonDataStore: BaseObservableStateStore<DetermineStatePersonData> {
    private let candidateAccountId: AccountId

    private var mainChange: DetermineStateSync.MainChange?
    private var personChange: DetermineStateSync.PersonChange?
    private var memberChange: DetermineStateSync.PersonChange?

    init(
        candidateAccountId: AccountId,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.candidateAccountId = candidateAccountId
        super.init(logger: logger)
    }
}

extension DetermineStatePersonDataStore: DetermineStateSyncServiceObserver {
    func determineStateSyncChanged(by change: DetermineStateSync.MainChange) {
        mutex.lock()

        defer {
            mutex.unlock()
        }

        if let state = stateObservable.state {
            mainChange = nil
            stateObservable.state = state.applying(change: change)
        } else {
            mainChange = change
            initializeStateIfPossible()
        }
    }

    func determineStateSyncChanged(by change: DetermineStateSync.PersonChange) {
        mutex.lock()

        defer {
            mutex.unlock()
        }

        if let state = stateObservable.state {
            personChange = nil
            stateObservable.state = state.applying(change: change)
        } else {
            personChange = change
            initializeStateIfPossible()
        }
    }
}

private extension DetermineStatePersonDataStore {
    func initializeStateIfPossible() {
        guard
            let mainChange,
            case let .defined(mobRuleAlias) = mainChange.mobRuleAlias,
            case let .defined(scoreAlias) = mainChange.scoreAlias,
            case let .defined(resourcesAlias) = mainChange.resourcesAlias,
            case let .defined(personId) = mainChange.personId,
            case let .defined(consumerInfo) = mainChange.consumerInfo
        else {
            printMissingDataWarning()
            return
        }

        guard mainChange.shouldWaitForPersonChange else {
            stateObservable.state = .init(
                candidateAccountId: candidateAccountId,
                mobRuleAlias: mobRuleAlias,
                scoreAlias: scoreAlias,
                resourcesAlias: resourcesAlias,
                personId: personId,
                personRecord: nil,
                memberRingPosition: nil,
                proofOfInkPerson: nil,
                consumerInfo: consumerInfo
            )
            return
        }

        guard
            let personChange,
            case let .defined(personRecord) = personChange.personRecord,
            case let .defined(memberRingPosition) = personChange.memberRingPosition,
            case let .defined(proofOfInkPerson) = personChange.proofOfInkPerson
        else {
            printMissingDataWarning()
            return
        }

        stateObservable.state = .init(
            candidateAccountId: candidateAccountId,
            mobRuleAlias: mobRuleAlias,
            scoreAlias: scoreAlias,
            resourcesAlias: resourcesAlias,
            personId: personId,
            personRecord: personRecord,
            memberRingPosition: memberRingPosition,
            proofOfInkPerson: proofOfInkPerson,
            consumerInfo: consumerInfo
        )
    }

    func printMissingDataWarning() {
        logger.warning("Change doesn't include all the data:")
        logger.warning(String(describing: mainChange))
        logger.warning(String(describing: personChange))
    }
}

struct DetermineStatePersonData: Equatable {
    fileprivate let candidateAccountId: AccountId
    fileprivate let mobRuleAlias: PeoplePallet.RevisedContextualAlias?
    fileprivate let scoreAlias: PeoplePallet.RevisedContextualAlias?
    fileprivate let resourcesAlias: PeoplePallet.RevisedContextualAlias?
    fileprivate let personId: PeoplePallet.PersonalId?
    fileprivate let personRecord: PeoplePallet.PersonRecord?
    fileprivate let memberRingPosition: MembersPallet.RingPosition?
    fileprivate let proofOfInkPerson: ProofOfInkPallet.Person?
    fileprivate let consumerInfo: ResourcesPallet.ConsumerInfo?
}

extension DetermineStatePersonData {
    /// The ring index from the member record, if the person is included.
    var ringIndex: MembersPallet.RingIndex? {
        memberRingPosition?.ringIndex
    }

    var hasReachedPersonhood: Bool {
        personId != nil
    }

    func makeAccountOrPerson() -> GamePallet.AccountOrPerson {
        guard let registeredData = makeRegisteredData() else {
            return .account(accountID: candidateAccountId)
        }
        switch registeredData.source {
        case .proofOfInk:
            return .person(alias: registeredData.scoreAlias.alias)
        case .game:
            return .account(accountID: candidateAccountId)
        }
    }

    func makeRegisteredData() -> People.RegisteredData? {
        .init(
            mobRuleAlias: mobRuleAlias,
            scoreAlias: scoreAlias,
            resourcesAlias: resourcesAlias,
            personId: personId,
            memberRingPosition: memberRingPosition,
            personRecord: personRecord,
            proofOfInkPerson: proofOfInkPerson,
            consumerInfo: consumerInfo
        )
    }
}

private extension DetermineStatePersonData {
    func applying(change: DetermineStateSync.MainChange) -> DetermineStatePersonData {
        .init(
            candidateAccountId: candidateAccountId,
            mobRuleAlias: change.mobRuleAlias.valueWhenDefined(else: mobRuleAlias),
            scoreAlias: change.scoreAlias.valueWhenDefined(else: scoreAlias),
            resourcesAlias: change.resourcesAlias.valueWhenDefined(else: resourcesAlias),
            personId: change.personId.valueWhenDefined(else: personId),
            personRecord: personRecord,
            memberRingPosition: memberRingPosition,
            proofOfInkPerson: proofOfInkPerson,
            consumerInfo: change.consumerInfo.valueWhenDefined(else: consumerInfo)
        )
    }

    func applying(change: DetermineStateSync.PersonChange) -> DetermineStatePersonData {
        .init(
            candidateAccountId: candidateAccountId,
            mobRuleAlias: mobRuleAlias,
            scoreAlias: scoreAlias,
            resourcesAlias: resourcesAlias,
            personId: personId,
            personRecord: change.personRecord.valueWhenDefined(else: personRecord),
            memberRingPosition: change.memberRingPosition.valueWhenDefined(else: memberRingPosition),
            proofOfInkPerson: change.proofOfInkPerson.valueWhenDefined(else: proofOfInkPerson),
            consumerInfo: consumerInfo
        )
    }
}

private extension People.RegisteredData {
    init?(
        mobRuleAlias: PeoplePallet.RevisedContextualAlias?,
        scoreAlias: PeoplePallet.RevisedContextualAlias?,
        resourcesAlias: PeoplePallet.RevisedContextualAlias?,
        personId: PeoplePallet.PersonalId?,
        memberRingPosition: MembersPallet.RingPosition?,
        personRecord: PeoplePallet.PersonRecord?,
        proofOfInkPerson: ProofOfInkPallet.Person?,
        consumerInfo: ResourcesPallet.ConsumerInfo?
    ) {
        guard
            let personId,
            let memberRingPosition,
            memberRingPosition.isIncluded,
            personRecord?.account != nil,
            let mobRuleAlias,
            mobRuleAlias.isRelevant(accordingTo: memberRingPosition),
            let scoreAlias,
            scoreAlias.isRelevant(accordingTo: memberRingPosition),
            let resourcesAlias,
            resourcesAlias.isRelevant(accordingTo: memberRingPosition),
            let consumerInfo,
            let liteUsername = Username(rawData: consumerInfo.liteUsername)
        else {
            return nil
        }

        let fullUsername: Username? =
            if let fullUsernameData = consumerInfo.fullUsername?.wrappedValue {
                Username(rawData: fullUsernameData)
            } else {
                nil
            }

        self.mobRuleAlias = mobRuleAlias.contextualAlias
        self.scoreAlias = scoreAlias.contextualAlias
        self.resourcesAlias = resourcesAlias.contextualAlias
        self.personId = personId
        self.liteUsername = liteUsername
        self.fullUsername = fullUsername

        if let proofOfInkPerson {
            source = .proofOfInk(proofOfInkPerson)
        } else {
            source = .game
        }
    }
}
