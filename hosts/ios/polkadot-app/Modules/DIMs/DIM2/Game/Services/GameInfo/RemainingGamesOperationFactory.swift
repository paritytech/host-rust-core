import Foundation
import SubstrateSdk
import SubstrateStorageQuery
import Operation_iOS
import Individuality

protocol RemainingGamesOperationMaking {
    func fetchResult(
        for accountOrPerson: GamePallet.AccountOrPerson,
        atBlock block: Data?
    ) async throws -> RemainingGamesResult
}

final class RemainingGamesOperationFactory {
    private let connection: JSONRPCEngine
    private let runtimeService: RuntimeCodingServiceProtocol
    private let resultFactory: RemainingGamesMaking
    private let storageRequestFactory: StorageRequestFactory

    init(
        connection: JSONRPCEngine,
        runtimeService: RuntimeCodingServiceProtocol,
        resultFactory: RemainingGamesMaking = RemainingGamesFactory(),
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue
    ) {
        self.connection = connection
        self.runtimeService = runtimeService
        self.resultFactory = resultFactory

        storageRequestFactory = StorageRequestFactory(
            remoteFactory: StorageKeyFactory(),
            operationManager: OperationManager(operationQueue: operationQueue)
        )
    }
}

extension RemainingGamesOperationFactory: RemainingGamesOperationMaking {
    func fetchResult(
        for accountOrPerson: GamePallet.AccountOrPerson,
        atBlock block: Data?
    ) async throws -> RemainingGamesResult {
        let codingFactory = try await runtimeService.fetchCoderFactoryOperation()
            .asyncExecute()

        async let requiredScore = fetchRequiredScore(
            codingFactory: codingFactory,
            atBlock: block
        )
        async let gameInfo = fetchGameInfo(
            codingFactory: codingFactory,
            atBlock: block
        )
        async let participant = fetchParticipant(
            codingFactory: codingFactory,
            for: accountOrPerson,
            atBlock: block
        )
        async let schedules = fetchSchedules(
            codingFactory: codingFactory,
            atBlock: block
        )

        return try await resultFactory.makeResult(input: .init(
            participant: participant,
            currentScore: makeCurrentScore(participant: participant),
            currentStreak: participant?.streak.makeIntegerStreak() ?? 0,
            requiredScore: requiredScore,
            overridedCurrentGameScore: gameInfo?.personhoodScoreOverride.map { Int($0) },
            overridedScheduledGameScores: makeOverridedScheduledGameScores(schedules: schedules)
        ))
    }
}

private extension RemainingGamesOperationFactory {
    func makeCurrentScore(participant: ScorePallet.Participant?) -> Int {
        guard let score = participant?.score else {
            return 0
        }
        return Int(score)
    }

    func makeOverridedScheduledGameScores(schedules: [GamePallet.GameSchedule]?) -> [Int?]? {
        guard let schedules else {
            return nil
        }
        return schedules.map {
            if let personhoodScoreOverride = $0.personhoodScoreOverride {
                Int(personhoodScoreOverride)
            } else {
                nil
            }
        }
    }

    func fetchRequiredScore(
        codingFactory: RuntimeCoderFactoryProtocol,
        atBlock block: Data?
    ) async throws -> Int {
        let fetchWrapper: CompoundOperationWrapper<
            StorageResponse<StringCodable<UInt8>>
        > = storageRequestFactory.queryItem(
            engine: connection,
            factory: { codingFactory },
            storagePath: ScorePallet.personhoodThreshold,
            at: block
        )
        guard let result = try await fetchWrapper.asyncExecute().value?.wrappedValue else {
            throw BaseOperationError.unexpectedDependentResult
        }
        return Int(result)
    }

    func fetchGameInfo(
        codingFactory: RuntimeCoderFactoryProtocol,
        atBlock block: Data?
    ) async throws -> GamePallet.GameInfo? {
        let fetchWrapper: CompoundOperationWrapper<
            StorageResponse<GamePallet.GameInfo>
        > = storageRequestFactory.queryItem(
            engine: connection,
            factory: { codingFactory },
            storagePath: GamePallet.game,
            at: block
        )
        return try await fetchWrapper.asyncExecute().value
    }

    func fetchParticipant(
        codingFactory: RuntimeCoderFactoryProtocol,
        for accountOrPerson: GamePallet.AccountOrPerson,
        atBlock block: Data?
    ) async throws -> ScorePallet.Participant? {
        let fetchWrapper: CompoundOperationWrapper<
            [StorageResponse<ScorePallet.Participant>]
        > = storageRequestFactory.queryItems(
            engine: connection,
            keyParams: { [accountOrPerson] },
            factory: { codingFactory },
            storagePath: ScorePallet.participants,
            at: block
        )
        return try await fetchWrapper.asyncExecute().first?.value
    }

    func fetchSchedules(
        codingFactory: RuntimeCoderFactoryProtocol,
        atBlock block: Data?
    ) async throws -> [GamePallet.GameSchedule]? {
        let fetchWrapper: CompoundOperationWrapper<
            StorageResponse<[GamePallet.GameSchedule]>
        > = storageRequestFactory.queryItem(
            engine: connection,
            factory: { codingFactory },
            storagePath: GamePallet.gameSchedules,
            at: block
        )
        return try await fetchWrapper.asyncExecute().value
    }
}
