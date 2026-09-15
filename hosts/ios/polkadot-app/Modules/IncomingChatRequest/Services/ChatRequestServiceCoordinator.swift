import Foundation
import CommonService
import MessageExchangeKit
import SDKLogger
import ChainStore

protocol ChatRequestCoordinatorServicing: ApplicationServiceProtocol {}

final class ChatRequestCoordinatorService {
    let contactsProviderFactory: ChatContactDataProviderMaking
    let messageProviderFactory: ChatMessageDataProviderMaking
    let serviceFactory: ChatRequestServiceMaking
    let logger: SDKLoggerProtocol

    private var coordinationTask: Task<Void, Never>?

    init(
        contactsProviderFactory: ChatContactDataProviderMaking,
        messageProviderFactory: ChatMessageDataProviderMaking,
        serviceFactory: ChatRequestServiceMaking,
        logger: SDKLoggerProtocol
    ) {
        self.contactsProviderFactory = contactsProviderFactory
        self.messageProviderFactory = messageProviderFactory
        self.serviceFactory = serviceFactory
        self.logger = logger
    }
}

extension ChatRequestCoordinatorService: ChatRequestCoordinatorServicing {
    func setup() {
        guard coordinationTask == nil else {
            logger.warning("Service already running")
            return
        }

        logger.debug("Starting service...")

        coordinationTask = Task {
            do {
                let discoveryService = try await serviceFactory.makeDiscoveryService()
                let incomingRequestService = try await serviceFactory.makeIncomingChatRequestService()
                let outgoingRequestService = try await serviceFactory.makeOutgoingChatRequestService()
                let incomingContext = try await serviceFactory.makeIncomingChatRequestContext()
                let outgoingContext = try await serviceFactory.makeOutgoingChatRequestContext()

                let allContactsStream = contactsProviderFactory.subscribeAllContacts()

                logger.debug("Service started")

                for try await contacts in allContactsStream {
                    await incomingContext.update(
                        contacts: contacts,
                        discoverTaskBuilder: { ownKeyId in
                            setupDiscoveryTask(
                                using: discoveryService,
                                ownKeyId: ownKeyId,
                                with: incomingContext
                            )
                        }, incomingRequestTaskBuilder: { contacts, ownKeyId in
                            setupIncomingRequestsTask(
                                for: contacts,
                                ownKeyId: ownKeyId,
                                using: incomingRequestService,
                                context: incomingContext
                            )
                        }
                    )

                    await outgoingContext.update(
                        contacts: contacts,
                        outgoingRequestTaskBuilder: {
                            setupOutgoingRequestsTask(
                                outgoingService: outgoingRequestService,
                                context: outgoingContext
                            )
                        }
                    )

                    logger.debug("Handled contacts: \(contacts.count)")
                }
            } catch {
                logger.error("Contacts subscription failed: \(error)")
            }

            logger.debug("Contacts stream ended")
        }
    }

    func throttle() {
        coordinationTask?.cancel()
        coordinationTask = nil
    }
}

private extension ChatRequestCoordinatorService {
    func setupDiscoveryTask(
        using discoveryService: ChatDiscoveryServicing,
        ownKeyId: Chat.Contact.Own,
        with context: IncomingChatRequestCoordinationContext
    ) -> Task<Void, Never> {
        Task {
            guard let discoveredRequestStream = discoveryService.makeDiscoveryTask(for: ownKeyId) else {
                logger.error("Discovery stream not created")
                return
            }

            do {
                for try await validatedRequest in discoveredRequestStream {
                    do {
                        try await context.handle(incomingRequest: validatedRequest, ownKeyId: ownKeyId)

                        logger.debug("Handled discovered request: \(validatedRequest.message.messageId)")
                    } catch {
                        logger.error("Couldn't handle discovered request: \(error)")
                    }
                }
            } catch {
                logger.error("Discovery requests subscription failed: \(error)")
            }

            logger.debug("Discovery stream ended")
        }
    }

    func setupIncomingRequestsTask(
        for contacts: [Chat.Contact],
        ownKeyId: Chat.Contact.Own,
        using incomingService: IncomingChatRequestServicing,
        context: IncomingChatRequestCoordinationContext
    ) -> Task<Void, Never> {
        Task {
            let peers = contacts.map { $0.toMessageExchangePeer() }

            let incomingRequestsStream = incomingService.subscribe(peers: Set(peers), ownKeyId: ownKeyId)

            do {
                for try await validatedRequest in incomingRequestsStream {
                    do {
                        try await context.handle(incomingRequest: validatedRequest, ownKeyId: ownKeyId)

                        logger.debug("Handled incoming request: \(validatedRequest.message.messageId)")
                    } catch {
                        logger.error("Couldn't handle incoming request: \(error)")
                    }
                }
            } catch {
                logger.error("Incoming requests subscription failed: \(error)")
            }

            logger.debug("Incoming requests stream ended")
        }
    }

    func setupOutgoingRequestsTask(
        outgoingService: OutgoingChatRequestServicing,
        context: OutgoingChatRequestCoordinationContext
    ) -> Task<Void, Never> {
        Task {
            let outgoingRequestsStream = messageProviderFactory.subscribeNewOutgoingChatRequests()

            do {
                for try await requestMessages in outgoingRequestsStream {
                    try await context.process(requestMessages: requestMessages) { message, peer, own in
                        try await outgoingService.send(message: message, to: peer, ownKeyId: own)
                    }
                }
            } catch {
                logger.error("Outgoing requests processing failed: \(error)")
            }

            logger.debug("Outgoing requests stream ended")
        }
    }
}
