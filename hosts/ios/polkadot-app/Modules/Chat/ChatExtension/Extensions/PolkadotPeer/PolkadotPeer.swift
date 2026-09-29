import Foundation
import UIKit
import PolkadotUI
import AsyncExtensions
import UIKitExt

final class PolkadotPeer: ChatExtensionBot, ChatExtensionDelegateProvidable {
    private let faqItems: [ChatExtensionActions.FAQ] = [
        .init(
            id: "who",
            question: String(localized: .ChatExtension.polkadotPeerFaqQuestionWho),
            answer: String(localized: .ChatExtension.polkadotPeerFaqAnswerWho)
        ),
        .init(
            id: "why",
            question: String(localized: .ChatExtension.polkadotPeerFaqQuestionWhy),
            answer: String(localized: .ChatExtension.polkadotPeerFaqAnswerWhy)
        ),
        .init(
            id: "other",
            question: String(localized: .ChatExtension.polkadotPeerFaqQuestionOther),
            answer: String(localized: .ChatExtension.polkadotPeerFaqAnswerOther)
        )
    ]

    weak var delegate: ChatExtensionDelegate? {
        get {
            wireframe.registryDelegate
        }

        set {
            wireframe.registryDelegate = newValue
        }
    }

    let actions: [ChatExtensionActions.ActionModel]
    let interactor: PolkadotPeerInteracting
    let wireframe: PolkadotPeerWireframeProtocol
    let logger: LoggerProtocol

    private var fullUsernameClaimedTask: Task<Void, Error>?
    private var personhoodRegisteredTask: Task<Void, Error>?

    private let footerContentConfiguration = AsyncCurrentValueSubject<(any HashableContentConfiguration)?>(nil)

    init(
        actions: [ChatExtensionActions.ActionModel],
        wireframe: PolkadotPeerWireframeProtocol,
        interactor: PolkadotPeerInteracting,
        logger: LoggerProtocol
    ) {
        self.actions = actions
        self.wireframe = wireframe
        self.interactor = interactor
        self.logger = logger
    }

    override func onTextMessage(
        _ message: Chat.LocalMessage,
        text _: String,
        context: ChatExtensionProcessingContextProtocol
    ) async -> ChatExtension.ProcessingResult {
        switch message.content {
        case let .extensionActionResponse(_, action):
            guard let item = faqItems.first(where: { $0.id == action }) else {
                return .skipped
            }
            Task {
                try await context.addNewMessage(
                    .text(item.answer),
                    delayDelivery: .custom(0.3),
                    chatExtension: self
                )
            }
            return .processed
        default:
            return .skipped
        }
    }
}

extension PolkadotPeer: ChatExtensionBotProtocol {
    nonisolated static let identifier: ChatExtension.Id = "PolkadotPeer"
    var identifier: ChatExtension.Id { Self.identifier }
    var peerMetadata: Chat.PeerMetadata {
        Chat.PeerMetadata(
            name: String(localized: .ChatExtension.chatTitlePolkadotPeer),
            contactSource: .chat,
            icon: .bot,
            input: .empty,
            moreActions: []
        )
    }

    func deliverAutomaticMessages(_ context: ChatExtensionDiscoverContextProtocol) {
        fullUsernameClaimedTask?.cancel()
        fullUsernameClaimedTask = Task { [weak self, interactor, context] in
            guard let self else { return }
            let processingContext = FullUsernameClaimedContext(context: context)
            try await processingContext.process(
                contentSequence: interactor.observeFullUsernameClaimed(),
                sender: self
            )
        }

        personhoodRegisteredTask?.cancel()
        personhoodRegisteredTask = Task { [weak self, interactor, context] in
            guard let self else { return }
            let processingContext = PersonhoodRegisteredContext(context: context)
            try await processingContext.process(
                sequence: interactor.observePersonhoodRegistered(),
                sender: self
            )
        }

        Task {
            await interactor.setup()

            let messages: [Chat.LocalMessage.Content] = [
                .text(String(localized: .ChatExtension.polkadotPeerWelcome1)),
                .staticTextImageContent(
                    Chat.LocalMessage.Content.StaticTextImageContent(
                        text: String(localized: .ChatExtension.polkadotPeerWelcome2),
                        media: .peerOption1
                    )
                ),
                .staticTextImageContent(
                    Chat.LocalMessage.Content.StaticTextImageContent(
                        text: String(localized: .ChatExtension.polkadotPeerWelcome3),
                        media: .peerOption2
                    )
                )
            ]

            try await context.setWelcomeMessages(
                from: self,
                with: { messages }
            )
        }

        Task { [weak self] in
            await self?.invalidateFooter(with: context)
        }
    }

    func process(
        action _: Chat.Action,
        context _: ChatExtensionActionContextProtocol
    ) async {}

    func attach(presentationView: ControllerBackedProtocol) {
        Task { @MainActor [wireframe] in
            wireframe.view = presentationView
        }
    }
}

extension PolkadotPeer: ChatExtensionActionProvidable {
    func contentConfiguration() async throws -> AnyAsyncSequence<(any HashableContentConfiguration)?> {
        footerContentConfiguration
            .removeDuplicates { lhs, rhs in
                switch (lhs, rhs) {
                case (nil, nil):
                    true
                case let (lhs?, rhs?):
                    AnyHashable(lhs) == AnyHashable(rhs)
                default:
                    false
                }
            }
            .eraseToAnyAsyncSequence()
    }
}

private extension PolkadotPeer {
    func invalidateFooter(with context: ChatExtensionDiscoverContextProtocol) async {
        do {
            let openActions = actions.map {
                let identifier = $0.identifier
                return ChatMessageActionView.ViewModel(
                    title: $0.title,
                    subtitle: $0.subtitle,
                    buttonTitle: String(localized: .ChatExtension.polkadotPeerActionOpen),
                    buttonAction: { [weak self] in
                        Task { @MainActor in
                            self?.wireframe.openChatWithExtension(identifier)
                        }
                    }
                )
            }

            let faqActions = try await faqActions(in: context)

            let configuration = PolkadotFooterConfiguration.footer(
                messages: faqActions,
                title: String(localized: .ChatExtension.polkadotPeerFooterTitle),
                actions: openActions
            )

            footerContentConfiguration.send(configuration)
        } catch {
            logger.error("Invalidation failed: \(error)")
        }
    }

    func faqActions(in context: ChatExtensionDiscoverContextProtocol) async throws -> [UIAction] {
        var faqActions: [UIAction] = []
        for faqItem in faqItems {
            let hasResponse = try await context.hasResponse(from: self, with: faqItem.id)
            guard !hasResponse else {
                continue
            }

            let action = UIAction(
                title: faqItem.question,
                handler: { [unowned self, context] action in
                    Task {
                        try await context.addActionResponse(
                            action.title,
                            action: faqItem.id,
                            delayDelivery: .immediate,
                            chatExtension: self
                        )
                    }
                }
            )
            faqActions.append(action)
        }

        return faqActions
    }
}
