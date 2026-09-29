import Foundation
import MessageExchangeKit
import StatementStore
import SubstrateSdk
import Individuality
import ChainRegistry

enum VideoGameSessionFactoryError: Error {
    case peerIdentifierNotFound
}

protocol VideoGameSessionMaking {
    func makeSession(
        gameIndex: GamePallet.GameIndex,
        peerAccountId: AccountId,
        delegate: AnyPeerSessionDelegate<OpaqueVideoGameSignalingEnvelope>,
        peerLogger: LoggerProtocol
    ) async throws -> VideoGameSignalingSession
}

final class VideoGameSessionFactory {
    private let ownSignKeyId: String
    private let serviceFactoryProvider: () -> MessageExchageServiceMaking
    private let identifierService: ChatIdentifierServiceProtocol
    private let chainRegistry: ChainRegistryProtocol
    private let chatChainId: ChainModel.Id

    init(
        ownSignKeyId: String,
        serviceFactoryProvider: @escaping () -> MessageExchageServiceMaking,
        identifierService: ChatIdentifierServiceProtocol,
        chainRegistry: ChainRegistryProtocol,
        chatChainId: ChainModel.Id = AppConfig.Chains.chatChain
    ) {
        self.ownSignKeyId = ownSignKeyId
        self.serviceFactoryProvider = serviceFactoryProvider
        self.identifierService = identifierService
        self.chainRegistry = chainRegistry
        self.chatChainId = chatChainId
    }
}

extension VideoGameSessionFactory: VideoGameSessionMaking {
    func makeSession(
        gameIndex: GamePallet.GameIndex,
        peerAccountId: AccountId,
        delegate: AnyPeerSessionDelegate<OpaqueVideoGameSignalingEnvelope>,
        peerLogger: LoggerProtocol
    ) async throws -> VideoGameSignalingSession {
        // Fetch peer's encryption identifier from CommunicationIdentifiers storage
        guard let peerIdentifier = try await identifierService.fetch(for: peerAccountId) else {
            throw VideoGameSessionFactoryError.peerIdentifierNotFound
        }

        // Build Own using game candidate derivation paths with the video game room PIN
        let own = MessageExchange.Own(
            signKeyId: ownSignKeyId,
            encryptionKeyId: Chat.Contact.Own.gameEncryptionKeyId(),
            pin: Constants.pin
        )

        // Build Peer with the fetched public key and PIN
        let peer = MessageExchange.Peer(
            accountId: peerAccountId,
            publicKey: peerIdentifier.localPublicKey.rawData,
            pin: Constants.pin,
            devices: []
        )

        // Each peer gets its own service factory
        let connection = try chainRegistry.getConnectionOrError(for: chatChainId)
        let serviceFactory = serviceFactoryProvider()

        let exchangeService = try serviceFactory.makeService(
            statementStoreConnection: StatementStoreConnection(
                connection: connection,
                retryMatcher: StatementSubmitErrorMatcher.retryWhenTimeoutOrNoAllowance(),
                logger: peerLogger
            ),
            delegate: delegate
        )

        // Register the session request so the service starts listening
        let sessionRequest = MessageExchange.SessionRequest(own: own, peer: peer)
        exchangeService.updateSessions([sessionRequest])

        return VideoGameSignalingSession(
            gameIndex: gameIndex,
            peerAccountId: peerAccountId,
            exchangeService: exchangeService,
            peer: peer,
            peerLogger: peerLogger
        )
    }
}

private extension VideoGameSessionFactory {
    enum Constants {
        static let pin = "video_game_room"
    }
}
