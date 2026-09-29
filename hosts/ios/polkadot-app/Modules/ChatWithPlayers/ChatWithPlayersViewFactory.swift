import Foundation
import UIKit
import MessageExchangeKit
import ChainRegistry

@MainActor
enum ChatWithPlayersViewFactory {
    static func createView(
        game: UInt32,
        gameDate: Date,
        chatFlowState: ChatFlowState
    ) -> ChatWithPlayersViewProtocol? {
        guard
            let dim2Extension = chatFlowState.extensionsRegistry.getChatExtensionBot(
                for: DIM2ChatExtension.identifier
            ) as? DIM2ChatExtending,
            let tld = try? DotNsTldProviderFacade.shared.currentTldOrError() else {
            return nil
        }

        let votes = GameVoteRepositoryFactory()
            .repository(forGame: game)
        let contacts = ChatContactRepositoryFactory()
            .createRepository(forFilter: nil)
        let logger = Logger.shared

        let identifierService = ChatIdentifierService(
            chainRegistry: ChainRegistryFacade.sharedRegistry,
            chain: AppConfig.Chains.chatChain,
            operationQueue: OperationManagerFacade.sharedDefaultQueue,
            logger: logger
        )

        let chatIdFactory = ChatPushIdFactory(
            encryptionManager: ChatEncryptionManager(),
            signManager: ChatSignerManager(),
            sessionIdFactory: PeerSessionIdFactory(),
            logger: logger
        )
        let storageFacade = UserDataStorageFacade.shared
        let service = ChatRequestStoreService(
            messageExchangeModeProvider: ChatMessageExchangeModeProvider(tld: tld),
            storageFacade: storageFacade,
            pushIdFactory: chatIdFactory,
            deviceEncryptionKeyManager: DeviceEncryptionKeyManager.shared
        )
        let pushToken = APNSTokenProviderFacade.sharedManager

        let interactor = ChatWithPlayersInteractor(
            gameIndex: game,
            gameDate: gameDate,
            repositoryVotes: votes,
            repositoryContacts: contacts,
            identifierService: identifierService,
            chatRequestService: service,
            personDataStore: dim2Extension.flowState.personDataStore,
            pushToken: pushToken.currentToken
        )

        let wireframe = ChatWithPlayersWireframe(flowState: chatFlowState)

        let presenter = ChatWithPlayersPresenter(
            interactor: interactor,
            wireframe: wireframe
        )

        let view = ChatWithPlayersViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter

        return view
    }
}
