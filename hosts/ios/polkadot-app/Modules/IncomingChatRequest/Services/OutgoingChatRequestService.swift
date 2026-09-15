import Foundation
import SubstrateSdk
import MessageExchangeKit
import StatementStore
import Operation_iOS
import SDKLogger

protocol OutgoingChatRequestServicing {
    func send(
        message: Chat.RequestMessage,
        to peer: MessageExchange.Peer,
        ownKeyId: MessageExchange.Own
    ) async throws
}

enum OutgoingChatRequestServiceError: Error {
    case unexpected(String)
}

final class OutgoingChatRequestService {
    private let statementStoreSubmitter: StatementStoreSubmitting
    private let statementSignManager: StatementStoreSignerManaging
    private let priorityFactory: StatementPriorityMaking
    private let requestFactory: ChatRequestFactoryProtocol
    private let channelFactory: ChatRequestChannelFactoryProtocol
    private let logger: SDKLoggerProtocol

    init(
        statementStoreSubmitter: StatementStoreSubmitting,
        statementSignManager: StatementStoreSignerManaging,
        requestFactory: ChatRequestFactoryProtocol,
        priorityFactory: StatementPriorityMaking,
        channelFactory: ChatRequestChannelFactoryProtocol,
        logger: SDKLoggerProtocol
    ) {
        self.statementStoreSubmitter = statementStoreSubmitter
        self.statementSignManager = statementSignManager
        self.priorityFactory = priorityFactory
        self.channelFactory = channelFactory
        self.requestFactory = requestFactory
        self.logger = logger
    }
}

extension OutgoingChatRequestService: OutgoingChatRequestServicing {
    func send(
        message: Chat.RequestMessage,
        to peer: MessageExchange.Peer,
        ownKeyId: MessageExchange.Own
    ) async throws {
        guard let pagination = ChatRequest.paginationDay(from: Date()) else {
            throw OutgoingChatRequestServiceError.unexpected("Invalid pagination day")
        }

        let topic1 = try ChatRequest.allPeerStatementsTopic(from: peer.accountId)
        let topic2 = try ChatRequest.paginationTopic(from: peer.accountId, day: pagination.day)
        let channel = try channelFactory.outgoingChannel(with: peer, ownKeyId: ownKeyId)

        let remoteRequest = try requestFactory.createRemoteRequest(
            from: message,
            peerEncryptionPubKey: peer.publicKey,
            peerAccountId: peer.accountId,
            ownKeyId: ownKeyId
        )

        let statementSigner = try statementSignManager.makeSigner(for: ownKeyId.signKeyId)

        let payload = try remoteRequest.scaleEncoded()
        let scaleEncodedPayload = try payload.scaleEncoded()

        let builder = StatementSubmitParametersBuilder(
            signer: statementSigner,
            logger: logger
        )
        .addTopic1(topic1)
        .addTopic2(topic2)
        .addTopic3(channel) // we add channel as topic2 also for easy discovery
        .addChannel(channel)
        .addExpiry(priorityFactory.makeTimestampPriority())
        .addScaleEncodedPayload(scaleEncodedPayload)

        try await statementStoreSubmitter.submitStatement(with: builder)
    }
}
