import UIKit
import Foundation
import Operation_iOS
import SubstrateSdk
import Individuality

protocol GameVoteServicing {
    func updateVoteCounter(
        votesToAdd votes: Int,
        for player: AccountId,
        gameIndex: GamePallet.GameIndex,
        isBanned: Bool
    ) async throws

    func updatePreviewImage(
        _ previewImage: UIImage?,
        for player: AccountId,
        gameIndex: GamePallet.GameIndex
    ) async throws

    func toggleVote(_ gameVote: GameVote) async throws
}

final class GameVoteService {
    private let repository: AnyDataProviderRepository<GameVote>
    private let operationQueue: OperationQueue
    private let logger: LoggerProtocol

    init(
        repositoryFactory: GameVoteRepositoryMaking = GameVoteRepositoryFactory(),
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        logger: LoggerProtocol = Logger.shared
    ) {
        repository = repositoryFactory.createRepository(forFilter: nil)
        self.operationQueue = operationQueue
        self.logger = logger
    }
}

extension GameVoteService: GameVoteServicing {
    func updateVoteCounter(
        votesToAdd votes: Int,
        for player: AccountId,
        gameIndex: GamePallet.GameIndex,
        isBanned: Bool
    ) async throws {
        let gameVote = try await performUpdate(
            for: player,
            gameIndex: gameIndex
        ) { gameVote in
            GameVote(
                gameIndex: gameIndex,
                accountId: player,
                voteCounter: gameVote.voteCounter + votes,
                isBanned: isBanned,
                previewImageData: gameVote.previewImageData,
                voteUpdateDate: Date()
            )
        }

        logger.debug("Vote counter updated: \(gameVote.voteCounter)")
    }

    func updatePreviewImage(
        _ previewImage: UIImage?,
        for player: AccountId,
        gameIndex: GamePallet.GameIndex
    ) async throws {
        let gameVote = try await performUpdate(
            for: player,
            gameIndex: gameIndex
        ) { gameVote in
            GameVote(
                gameIndex: gameIndex,
                accountId: player,
                voteCounter: gameVote.voteCounter,
                isBanned: gameVote.isBanned,
                previewImageData: previewImage?.jpegData(compressionQuality: 0.85),
                voteUpdateDate: gameVote.voteUpdateDate
            )
        }

        logger.debug("Preview image updated: \(gameVote.previewImageData == nil ? "nil" : "non-nil")")
    }

    func toggleVote(_ gameVote: GameVote) async throws {
        let updatedVote = try await performUpdate(
            for: gameVote.accountId,
            gameIndex: gameVote.gameIndex
        ) { currentVote in
            GameVote(
                gameIndex: currentVote.gameIndex,
                accountId: currentVote.accountId,
                voteCounter: currentVote.isPerson ? -1 : 1,
                isBanned: currentVote.isBanned,
                previewImageData: currentVote.previewImageData,
                voteUpdateDate: currentVote.voteUpdateDate
            )
        }

        logger.debug("Game vote toggled; voteCounter = \(updatedVote.voteCounter)")
    }
}

private extension GameVoteService {
    func performUpdate(
        for player: AccountId,
        gameIndex: GamePallet.GameIndex,
        updateClosure: (GameVote) -> GameVote
    ) async throws -> GameVote {
        let identifier = GameVote.makeIdentifier(
            gameIndex: gameIndex,
            player: player
        )

        let fetchOperation = repository.fetchOperation(by: { identifier }, options: .init())
        let existingVote = try await fetchOperation.asyncExecute()

        let currentVote = existingVote ?? GameVote(
            gameIndex: gameIndex,
            accountId: player,
            voteCounter: 0,
            isBanned: false,
            previewImageData: nil,
            voteUpdateDate: nil
        )

        let updatedVote = updateClosure(currentVote)

        let saveOperation = repository.saveOperation({ [updatedVote] }, { [] })
        try await saveOperation.asyncExecute()

        return updatedVote
    }
}
