import Foundation
import MessageExchangeKit
import SubstrateSdk
import SubstrateSdkExt
import Operation_iOS

final class PlayerContactOperationFactory {
    private let gameVotesRepositoryFactory: GameVoteRepositoryMaking
    let usernameGenerator: UsernameGeneratorProtocol
    let identifierService: ChatIdentifierServiceProtocol

    init(
        gameVotesRepositoryFactory: GameVoteRepositoryMaking,
        identifierService: ChatIdentifierServiceProtocol,
        usernameGenerator: UsernameGeneratorProtocol = UsernameGenerator()
    ) {
        self.gameVotesRepositoryFactory = gameVotesRepositoryFactory
        self.identifierService = identifierService
        self.usernameGenerator = usernameGenerator
    }
}

extension PlayerContactOperationFactory: RemoteContactResolving {
    func fetch(by accountId: AccountId) async throws -> Chat.RemoteContact? {
        let votes = try await gameVotesRepositoryFactory.repository(forAccount: accountId)
            .fetchAllOperation(with: .init())
            .asyncExecute()

        // Create RemoteContact only when there's a locally saved player e.g. when the user was in a game with the
        // remote contact
        guard let vote = votes.first else {
            return nil
        }

        guard let identifier = try await identifierService.fetch(for: accountId) else {
            return nil
        }

        return Chat.RemoteContact(
            accountId: accountId,
            username: usernameGenerator.generate(from: accountId),
            chatPublicKey: identifier.localPublicKey,
            imageData: vote.previewImageData,
            source: .game(vote.gameIndex, vote.voteUpdateDate)
        )
    }
}
