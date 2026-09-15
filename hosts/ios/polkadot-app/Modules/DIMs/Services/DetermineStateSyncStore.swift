import Foundation
import CommonService

final class DetermineStateSyncStore: BaseObservableStateStore<DetermineStateSyncState> {
    static let defaultRequiredScore: UInt32 = 0

    private var mainChange: DetermineStateSync.MainChange?
    private var personChange: DetermineStateSync.PersonChange?
    private var gameInfoSubscriptionResult: GameInfoSubscriptionResult?
    private var scoreInfoSubscriptionResult: ScoreInfoSubscriptionResult?
}

extension DetermineStateSyncStore: DetermineStateSyncServiceObserver {
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

extension DetermineStateSyncStore: GameInfoSyncServiceObserving {
    func gameInfoSubscriptionResultChanged(_ result: GameInfoSubscriptionResult) {
        mutex.lock()

        defer {
            mutex.unlock()
        }

        if let state = stateObservable.state {
            gameInfoSubscriptionResult = nil
            stateObservable.state = state.applying(result: result)
        } else {
            gameInfoSubscriptionResult = result
            initializeStateIfPossible()
        }
    }
}

extension DetermineStateSyncStore: ScoreInfoSyncServiceObserving {
    func scoreInfoSubscriptionResultChanged(_ result: ScoreInfoSubscriptionResult) {
        mutex.lock()

        defer {
            mutex.unlock()
        }

        if let state = stateObservable.state {
            scoreInfoSubscriptionResult = nil
            stateObservable.state = state.applying(result: result)
        } else {
            scoreInfoSubscriptionResult = result
            initializeStateIfPossible()
        }
    }
}

private extension DetermineStateSyncStore {
    func initializeStateIfPossible() {
        guard
            let mainChange,
            let gameInfoSubscriptionResult,
            let scoreInfoSubscriptionResult,
            case let .defined(candidate) = mainChange.candidate,
            case let .defined(mobRuleAlias) = mainChange.mobRuleAlias,
            case let .defined(scoreAlias) = mainChange.scoreAlias,
            case let .defined(resourcesAlias) = mainChange.resourcesAlias,
            case let .defined(personId) = mainChange.personId,
            case let .defined(identity) = mainChange.identity,
            case let .defined(consumerInfo) = mainChange.consumerInfo,
            case let .defined(gamePlayer) = gameInfoSubscriptionResult.player,
            case let .defined(gameParticipant) = scoreInfoSubscriptionResult.participant,
            case let .defined(personhoodThreshold) = scoreInfoSubscriptionResult.personhoodThreshold
        else {
            printMissingDataWarning()
            return
        }

        let requiredScore = personhoodThreshold ?? DetermineStateSyncStore.defaultRequiredScore

        guard mainChange.shouldWaitForPersonChange else {
            logger.debug("State updated without person waiting")

            stateObservable.state = .init(
                candidate: candidate,
                mobRuleAlias: mobRuleAlias,
                scoreAlias: scoreAlias,
                resourcesAlias: resourcesAlias,
                personId: personId,
                identity: identity,
                gamePlayer: gamePlayer,
                gameParticipant: gameParticipant,
                personRecord: nil,
                memberRingPosition: nil,
                proofOfInkPerson: nil,
                consumerInfo: consumerInfo,
                requiredScore: Int(requiredScore)
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

        logger.debug("State updated with person waiting")

        stateObservable.state = .init(
            candidate: candidate,
            mobRuleAlias: mobRuleAlias,
            scoreAlias: scoreAlias,
            resourcesAlias: resourcesAlias,
            personId: personId,
            identity: identity,
            gamePlayer: gamePlayer,
            gameParticipant: gameParticipant,
            personRecord: personRecord,
            memberRingPosition: memberRingPosition,
            proofOfInkPerson: proofOfInkPerson,
            consumerInfo: consumerInfo,
            requiredScore: Int(requiredScore)
        )
    }

    func printMissingDataWarning() {
        logger.warning("Change doesn't include all the data:")
        logger.warning(String(describing: mainChange))
        logger.warning(String(describing: personChange))
        logger.warning(String(describing: gameInfoSubscriptionResult))
        logger.warning(String(describing: scoreInfoSubscriptionResult))
    }
}
